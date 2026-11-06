"""05_network/parsers/cisco_ios.py — Cisco IOS `show running-config` 텍스트 파싱 헬퍼.

실제 장비 없이 미리 수집된 설정 텍스트 파일만으로 판정하므로(오프라인
설정파일 분석), 이 모듈은 정규식/블록 파싱만 제공하고 판정 로직은 각 checks/cisco_ios/N-xx.py
에 둔다. Cisco IOS 설정에서 하위 명령은 정확히 공백 1칸으로 들여쓰기되고, 최상위 명령/`!` 구분자는
들여쓰기가 없다 — 이 규칙으로 블록(line/interface 등)을 구분한다.
"""
from __future__ import annotations

import re
import secrets
import string


# 다른 Cisco 플랫폼(NX-OS·ASA·IOS XR)의 설정 표지. 이 설정들도 `hostname`/`interface`/`version` 줄이 있어 예전 detect()
# 가 IOS 로 판정했고, 그러면 설정 부재를 근거로 하는 항목(N-17/21/27/35 등)이 거짓 GOOD 이 되고 NX-OS `priv <key>` 같은
# 비밀값이 마스킹되지 않은 채 증적에 남았다(외부 검수 A14). 이런 입력은 IOS check 로 판정하지 않고 거부한다.
_OTHER_PLATFORMS = [
    ("Cisco NX-OS", re.compile(r"^version \d+\.\d+\(\d+\)|^!Command: show running-config|^feature \S+|^boot nxos\b|^vdc \S+", re.M)),
    ("Cisco ASA/PIX/FWSM", re.compile(r"^(?:ASA|PIX|FWSM) Version \d|^: Saved\s*$|^\s+nameif \S+", re.M)),
    ("Cisco IOS XR", re.compile(r"^!! IOS XR Configuration|^RP/\d+/", re.M)),
]


def other_platform(text: str) -> str | None:
    """IOS 가 아닌 Cisco 플랫폼 설정이면 그 이름을, 아니면 None. run.py 는 -e cisco_ios 로 강제 지정해도 거부한다."""
    for name, pat in _OTHER_PLATFORMS:
        if pat.search(text):
            return name
    return None


def completeness_problem(text: str) -> str | None:
    """설정이 끝까지 수집됐는지 확인한다. `show running-config`/`show startup-config` 는 마지막에 최상위 `end` 줄이
    있다 - 없으면(복사 중 잘림, 페이지 출력 중단 등) 뒤쪽 설정이 빠졌을 수 있어 "설정 없음"을 근거로 한 GOOD/NA 를
    낼 수 없다(외부 검수 A14, S6). `end` 뒤에는 빈 줄·프롬프트(`Router#`)만 허용한다. 문제가 없으면 None."""
    lines = [ln.rstrip() for ln in text.splitlines()]
    idx = None
    for i, ln in enumerate(lines):
        if ln == "end":
            idx = i
    if idx is None:
        return "설정 마지막의 `end` 줄이 없음(수집 중 잘린 설정일 수 있음)"
    if any(not re.match(r"^\S+[#>]\s*$", ln) for ln in lines[idx + 1:] if ln.strip()):
        return "`end` 줄 뒤에 설정으로 보이는 줄이 더 있음(여러 설정이 섞였거나 잘린 출력일 수 있음)"
    return None


def detect(text: str) -> bool:
    if other_platform(text):
        return False
    if re.search(r"^version \d+\.\d+\s*$", text, re.M):
        return True
    if "Building configuration" in text or "Current configuration" in text:
        return True
    if re.search(r"^hostname \S+", text, re.M) and re.search(r"^interface \S+", text, re.M):
        return True
    return False


def get_blocks(lines: list[str], header_re: str) -> list[list[str]]:
    """header_re 에 매치되는 최상위(들여쓰기 없는) 줄부터, 다음 최상위 줄 전까지를 블록으로 반환."""
    pattern = re.compile(header_re)
    blocks: list[list[str]] = []
    i, n = 0, len(lines)
    while i < n:
        if pattern.match(lines[i]):
            body = [lines[i]]
            j = i + 1
            while j < n and lines[j].startswith(" "):
                body.append(lines[j])
                j += 1
            blocks.append(body)
            i = j
        else:
            i += 1
    return blocks


_L3_ADDR = re.compile(r"^\s*(?:ip address (?:\d|dhcp\b|negotiated\b|pool\b)|ip unnumbered \S)", re.M)


class Ctx:
    """check 함수에 전달되는 파싱 컨텍스트. 원문 전체 검색 + line/interface 블록 접근을 제공한다."""

    def __init__(self, text: str):
        self.text = text
        self.lines = text.splitlines()
        self.line_blocks = get_blocks(self.lines, r"^line (con|vty|aux|tty) ")
        self.interface_blocks = get_blocks(self.lines, r"^interface \S+")

    def has(self, pattern: str) -> bool:
        return re.search(pattern, self.text, re.M) is not None

    def find(self, pattern: str) -> list:
        return re.findall(pattern, self.text, re.M)

    def search(self, pattern: str):
        return re.search(pattern, self.text, re.M)

    def line_block_text(self, kind: str) -> list[str]:
        """kind: con|vty|aux|tty. 해당 종류의 line 블록들을 각각 하나의 문자열로 합쳐 리스트로 반환."""
        out = []
        for b in self.line_blocks:
            if re.match(rf"^line {kind} ", b[0]):
                out.append("\n".join(b))
        return out

    def ip_interface_blocks(self) -> list[str]:
        """IP 주소가 설정되어 있고 shutdown 되지 않은 인터페이스 블록만 문자열로 반환
        (물리적으로 사용 중인 L3 인터페이스만 대상으로 per-interface 항목을 판정하기 위함).
        고정 주소뿐 아니라 `ip address dhcp`·`negotiated`·`pool`·`ip unnumbered` 도 L3 인터페이스다 - 예전에는 숫자
        주소만 봐서 DHCP 인터페이스를 대상에서 빼고 proxy-arp 등이 켜져 있어도 GOOD 을 냈다(외부 검수 A12)."""
        out = []
        for b in self.interface_blocks:
            body = "\n".join(b)
            if _L3_ADDR.search(body) and not re.search(r"^\s*shutdown\s*$", body, re.M):
                out.append(body)
        return out


def iface_name(block_text: str) -> str:
    """interface/line 블록(문자열, 첫 줄이 헤더)에서 이름만 추출. 예: "interface GigabitEthernet0/1" -> "GigabitEthernet0/1"."""
    first = block_text.splitlines()[0]
    parts = first.split(None, 1)
    return parts[1] if len(parts) > 1 else first


def exec_timeout_seconds(block_text: str) -> int | None:
    """line 블록의 exec-timeout 을 초 단위로 반환(미설정이면 None). `exec-timeout <분> [<초>]` - 초는 생략 가능하고
    `exec-timeout 0 0` 은 시간 제한 해제(무제한)를 뜻한다. 예전 check(N-07)는 분만 보고 초를 버려 `0 0`(무제한)과
    `10 30`(10분 30초)을 양호로 판정했고, 초를 생략한 줄은 미설정으로 봤다(판정 양방향 검증 중 발견, N-R1).
    같은 지시어가 여러 번이면 IOS 처럼 마지막 줄이 적용된다."""
    found = re.findall(r"^\s*exec-timeout (\d+)(?:[ \t]+(\d+))?[ \t]*$", block_text, re.M)
    if not found:
        return None
    mins, secs = found[-1]
    return int(mins) * 60 + int(secs or 0)


def banners(ctx) -> list[tuple[str, str]]:
    """`banner <motd|login|exec|incoming> <구분자>...<구분자>` 를 (종류, 본문) 목록으로 반환한다.
    show running-config 는 구분자를 `^C` 로 보여주지만 직접 입력한 설정은 임의의 한 글자(#, % 등)일 수 있다."""
    out = []
    lines = ctx.lines
    i, n = 0, len(lines)
    while i < n:
        m = re.match(r"^banner (motd|login|exec|incoming)[ \t]+(\S.*)$", lines[i])
        if not m:
            i += 1
            continue
        kind, rest = m.group(1), m.group(2)
        delim = "^C" if rest.startswith("^C") else rest[0]
        after = rest[len(delim):]
        if delim in after:
            out.append((kind, after.split(delim, 1)[0]))
            i += 1
            continue
        body = [after] if after.strip() else []
        j = i + 1
        while j < n and delim not in lines[j]:
            body.append(lines[j])
            j += 1
        if j < n:
            head = lines[j].split(delim, 1)[0]
            if head.strip():
                body.append(head)
        out.append((kind, "\n".join(body)))
        i = j + 1
    return out


BANNER_WARN = re.compile(r"authori[sz]|prohibit|monitor|warning|경고|무단|불법|비인가|인가된|금지", re.I)
_BANNER_INFO = [
    (re.compile(r"\$\((?:hostname|domain)\)", re.I), "$(hostname)/$(domain) 토큰"),
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"), "IP 주소"),
    (re.compile(r"\bIOS\b|\bversion\s*\d", re.I), "OS/버전 정보"),
    (re.compile(r"\b(?:cisco|catalyst|nexus|isr\d*|asr\d*)\b", re.I), "제조사/모델 정보"),
]


def banner_leaks(text: str, hostname: str | None) -> list[str]:
    """배너 본문에 드러난 시스템 정보 종류(N-10 취약 기준 "시스템 관련 정보 노출"). check 와 fix 가 같이 쓴다."""
    leaks = [label for pat, label in _BANNER_INFO if pat.search(text)]
    if hostname and len(hostname) >= 3 and re.search(rf"(?<![\w-]){re.escape(hostname)}(?![\w-])", text, re.I):
        leaks.append(f"호스트명({hostname})")
    return leaks


def vty_allows_telnet(block_text: str) -> bool:
    """line vty 블록이 telnet 을 허용하는지. transport input 이 없으면 기본값(all)=허용.
    여러 프로토콜을 나열한 줄(`transport input ssh telnet`)도 토큰 단위로 본다(X-03, 예전 정규식은 첫 토큰만 봄).
    같은 지시어가 여러 번이면 IOS 처럼 마지막 줄이 적용된다."""
    lines = [ln.split() for ln in block_text.splitlines() if re.match(r"^\s*transport input\b", ln)]
    if not lines:
        return True
    tokens = {t.lower() for t in lines[-1][2:]}
    return bool(tokens & {"all", "telnet"})


# ---- ACL 실효성 (외부 검수 A13) -------------------------------------------------------------------------
# N-06(VTY access-class)·N-19(SNMP community ACL)·N-27(ip http access-class) 은 ACL 을 "참조하는 줄"만 보고 GOOD 을
# 냈다. 참조한 ACL 이 정의되어 있지 않으면 IOS 는 접근을 제한하지 않고, `permit any` 가 있으면 사실상 무제한이다.
def acl_entries(ctx, name: str) -> list[str] | None:
    """ACL 규칙 줄(permit/deny ..., 순번·remark 제외) 목록. 번호 ACL(`access-list N ...`)과 이름/번호 블록
    (`ip access-list standard|extended X`)을 모두 본다. 정의가 없으면 None."""
    found = False
    out: list[str] = []
    for ln in ctx.lines:
        m = re.match(rf"^access-list {re.escape(name)}\s+(.*)$", ln)
        if m:
            found = True
            out.append(m.group(1).strip())
    for b in get_blocks(ctx.lines, rf"^ip access-list (?:standard|extended) {re.escape(name)}\s*$"):
        found = True
        out += [re.sub(r"^\d+\s+", "", ln.strip()) for ln in b[1:]]
    if not found:
        return None
    return [e for e in out if e and re.match(r"^(?:permit|deny)\b", e)]


def _src_is_any(tokens: list[str]) -> bool:
    if not tokens:
        return False
    if tokens[0] == "any":
        return True
    return len(tokens) > 1 and re.match(r"^\d+\.\d+\.\d+\.\d+$", tokens[0]) is not None and tokens[1] == "255.255.255.255"


def acl_entry_permits_any(entry: str) -> bool:
    """규칙 하나가 출발지 any 를 허용하는지. standard(`permit any`, `permit 0.0.0.0 255.255.255.255`)와
    extended(`permit <프로토콜> any ...`) 를 모두 본다."""
    t = entry.split()
    if not t or t[0] != "permit" or len(t) < 2:
        return False
    if _src_is_any(t[1:]):
        return True
    if t[1] == "host" or re.match(r"^\d+\.\d+\.\d+\.\d+$", t[1]):
        return False  # standard 의 특정 출발지
    return _src_is_any(t[2:])  # extended: permit <프로토콜> <출발지> ...


def acl_problem(ctx, name: str | None) -> str | None:
    """참조한 ACL 이 접근을 실제로 제한하지 못하는 이유(정의 없음/규칙 없음/any 허용). 문제가 없으면 None."""
    if not name:
        return "ACL 이 지정되지 않음"
    entries = acl_entries(ctx, name)
    if entries is None:
        return f"참조한 ACL {name} 이(가) 설정에 정의되어 있지 않음(접근 제한 없음)"
    if not entries:
        return f"참조한 ACL {name} 에 permit/deny 규칙이 없음"
    anys = [e for e in entries if acl_entry_permits_any(e)]
    if anys:
        return f"참조한 ACL {name} 이(가) 모든 출발지를 허용함({anys[0]}) - 사실상 접근 제한 없음"
    return None


def acl_evidence(ctx, name: str | None) -> str:
    entries = acl_entries(ctx, name) if name else None
    if entries is None:
        return f"ACL {name}: (정의 없음)" if name else ""
    return f"ACL {name}: " + " / ".join(entries)


def vty_access_class(block_text: str) -> str | None:
    """line vty 블록의 inbound access-class ACL 이름(없으면 None). 여러 줄이면 IOS 처럼 마지막 줄."""
    found = re.findall(r"^\s*access-class (\S+) in\b", block_text, re.M)
    return found[-1] if found else None


def vty_acl_problems(ctx) -> list[tuple[str, str]]:
    """접근 제한이 실효성 없는 VTY 블록과 그 이유 목록. checks/fixes N-06 이 같은 기준을 쓴다."""
    out = []
    for b in ctx.line_block_text("vty"):
        acl = vty_access_class(b)
        problem = acl_problem(ctx, acl) if acl else "access-class(ACL) 설정 없음"
        if problem:
            out.append((b, problem))
    return out


# ---- AAA 로그인 인증 목록 (외부 검수 A11) -----------------------------------------------------------------
def aaa_login_lists(ctx) -> dict[str, list[str]]:
    """`aaa authentication login <목록> <방식...>` 을 {목록: 방식 목록} 으로. 같은 목록이 여러 번이면 IOS 처럼 마지막."""
    out: dict[str, list[str]] = {}
    for ln in ctx.lines:
        m = re.match(r"^aaa authentication login (\S+)\s+(.+?)\s*$", ln)
        if m:
            out[m.group(1)] = m.group(2).split()
    return out


def aaa_methods_authenticate(methods: list[str] | None) -> bool:
    """방식 목록이 실제로 인증을 요구하는지. `none` 만 있으면 무인증이다(P-11 수정 이후 `default none` 도 GOOD 이던
    문제, A11). `group tacacs+ none` 처럼 none 이 대체 방식으로만 있으면 인증 요구로 본다."""
    return bool(methods) and any(m != "none" for m in methods)


def vty_line_authenticated(ctx, block_text: str) -> bool:
    """VTY 라인 블록이 접속 시 인증을 요구하는지. check(N-01)와 fix(N-01)가 같이 쓴다.
    - `no login` 은 password 줄이 있어도 비밀번호 없이 접속을 허용한다(진단 검수 D-R10).
    - aaa new-model 이면 라인의 `login authentication <목록>`(없으면 default 목록)이 적용된다(P-11). 그 목록이
      none 뿐이면 무인증(A11). 목록이 정의되지 않았으면 예전과 같이 라인의 password/login local 을 본다."""
    if re.search(r"^\s*no login\s*$", block_text, re.M):
        return False
    lists = aaa_login_lists(ctx)
    if ctx.has(r"^aaa new-model\s*$"):
        m = re.search(r"^\s*login authentication (\S+)", block_text, re.M)
        name = m.group(1) if m else "default"
        if name in lists:
            return aaa_methods_authenticate(lists[name])
    if re.search(r"^\s*password \S+", block_text, re.M):
        return True
    if re.search(r"^\s*login local\s*$", block_text, re.M):
        return True
    m = re.search(r"^\s*login authentication (\S+)", block_text, re.M)
    if m:
        return aaa_methods_authenticate(lists.get(m.group(1))) if m.group(1) in lists else True
    return False


SNMP_DEFAULT_COMMUNITIES = {"public", "private"}


def snmp_community_weak(s: str) -> bool:
    """checks/cisco_ios/N-18.py 와 동일한 복잡성 기준(3종류 이상 조합, 8자리 이상). N-18/19/20의
    fixes/cisco_ios/N-xx.py 가 같은 SNMP community 라인을 서로 다른 조건(문자열 취약/ACL 없음/RW)
    으로 동시에 건드려 재발급 명령이 서로를 덮어쓰는 문제가 있었다(실기 테스트로 발견, N-19/N-20
    주석 참고) - 이 헬퍼로 "문자열이 약한 라인은 N-18이 전담"하도록 책임을 명확히 나눈다."""
    if s.lower() in SNMP_DEFAULT_COMMUNITIES:
        return True
    if len(s) < 8:
        return True
    classes = sum(bool(re.search(p, s)) for p in (r"[A-Z]", r"[a-z]", r"\d", r"[^A-Za-z0-9]"))
    return classes < 3


def parse_snmp_community(line: str) -> dict | None:
    """`snmp-server community <string> [view <name>] [RO|RW] [ipv6 <acl>] [<acl>]` 한 줄을 해석한다.
    예전 정규식(`<string> [RO|RW] [acl]$`)은 view·ipv6 토큰이 있는 줄을 아예 놓쳐 N-19/N-20 이 그 줄을
    빼고 판정했다(진단 검수 D-R10). mode 는 생략 시 None(IOS 기본값 RW 해석은 check 가 한다)."""
    tokens = line.split()
    if len(tokens) < 3 or tokens[0] != "snmp-server" or tokens[1] != "community":
        return None
    info = {"string": tokens[2], "view": None, "mode": None, "acl": None, "ipv6_acl": None, "rest": tokens[3:]}
    rest = tokens[3:]
    i = 0
    while i < len(rest):
        t = rest[i]
        if t == "view" and i + 1 < len(rest):
            info["view"] = rest[i + 1]
            i += 2
            continue
        if t == "ipv6" and i + 1 < len(rest):
            info["ipv6_acl"] = rest[i + 1]
            i += 2
            continue
        if t in ("RO", "RW", "ro", "rw"):
            info["mode"] = t.upper()
        elif info["acl"] is None:
            info["acl"] = t
        i += 1
    return info


def snmp_acl_problem(ctx, info: dict) -> str | None:
    """community 줄의 IPv4 ACL 이 접근을 실제로 제한하지 못하는 이유(미지정/미정의/any 허용, 외부 검수 A13).
    checks N-19 와 fixes N-18/19/20 이 같은 기준으로 대상 줄을 나눈다. 문제가 없으면 None."""
    return acl_problem(ctx, info.get("acl"))


def snmp_community_lines(ctx) -> list[str]:
    """snmp-server community 로 시작하는 최상위 줄 전체(줄 끝 공백 제거)."""
    return [l.rstrip() for l in ctx.lines if re.match(r"^snmp-server community \S+", l)]


def snmp_communities(ctx) -> list[dict]:
    """parse_snmp_community 로 해석한 community 줄 목록. fixes/cisco_ios/N-18~20 이 진단(checks)과 같은 해석을
    쓰도록 한다 - 조치가 옛 정규식(`<string> [RO|RW] [acl]$`)을 써서 view·ipv6 토큰이 있는 줄은 명령을 만들지
    못하고 수동 안내로 빠졌다(조치 후속 F-R7)."""
    out = []
    for line in snmp_community_lines(ctx):
        info = parse_snmp_community(line)
        if info is not None:
            out.append(info)
    return out


def build_snmp_community(string: str, mode: str, view: str | None = None, ipv6_acl: str | None = None,
                         acl: str | None = None) -> str:
    """IOS 문법 순서(`<string> [view <name>] [RO|RW] [ipv6 <acl>] [<acl>]`)로 community 줄을 다시 만든다.
    재발급할 때 원래 줄의 view·ipv6 ACL 을 잃지 않기 위함이다."""
    parts = ["snmp-server", "community", string]
    if view:
        parts += ["view", view]
    parts.append(mode)
    if ipv6_acl:
        parts += ["ipv6", ipv6_acl]
    if acl:
        parts.append(acl)
    return " ".join(parts)


# ---- 비밀값 마스킹 (운영 안전 기준 S5, 진단 검수 D-R4) ---------------------------------
# N-17 이 snmp-server 줄 원문(community 평문·SNMPv3 auth/priv 키)을, N-01/06/08/09 가 VTY/AUX 블록 전체
# (평문 password, type 7 값)를 증적에 그대로 남겼다. 각 check 에서 빠뜨려도 새지 않도록 run.py 가 모든
# detail/evidence 에 이 함수를 한 번 더 적용한다(이중 방어). 값 자리만 <masked> 로 바꾸고 명령 형태는 남긴다.
_MASK = "<masked>"
_SECRET_PATTERNS = [
    # snmp-server community <string> ...
    (re.compile(r"(\bsnmp-server\s+community\s+)\S+", re.I), r"\1<community>"),
    # snmp-server host <addr> [vrf <이름>] [informs|traps] [version 1|2c|3 [auth|noauth|priv]] <community> ...
    # (vrf 를 빠뜨려 vrf 이름이 가려지고 community 원문이 남았다 - 실무 적용 검증 P-01)
    (re.compile(r"(\bsnmp-server\s+host\s+\S+(?:\s+vrf\s+\S+)?(?:\s+(?:informs|traps))?(?:\s+version\s+(?:1|2c|3(?:\s+(?:auth|noauth|priv))?))?\s+)(?!version\b|informs\b|traps\b)\S+", re.I), r"\1<community>"),
    # SNMPv3 user: ... auth md5|sha* <key> priv des|3des|aes [128|192|256] <key>
    (re.compile(r"(\bauth\s+(?:md5|sha\S*)\s+)\S+", re.I), r"\1" + _MASK),
    (re.compile(r"(\bpriv\s+(?:des\S*|3des|aes(?:\s+\d+)?)\s+)\S+", re.I), r"\1" + _MASK),
    # 알고리즘 없이 바로 키가 오는 형태(NX-OS `priv <key>`, `priv aes-128 <key>`). run.py 가 비 IOS 입력을 거부하지만
    # 이중 방어로 가린다(외부 검수 A14). 이미 가린 값은 건너뛴다.
    (re.compile(r"(\bsnmp-server\s+user\b.*?\bpriv\s+(?:aes-128\s+)?)(?!<)(?!(?:des\S*|3des|aes)(?:\s|$))\S+", re.I), r"\1" + _MASK),    # password|secret [암호화 타입 숫자] <값>  (enable/username/line/ppp chap 등 공통)
    # run.py 가 detail 에도 적용하므로 한글 문장("enable secret 또는 ...")은 값으로 보지 않는다(P-10).
    (re.compile(r"(\b(?:password|secret)(?:\s+\d{1,2})?\s+)(?![가-힣])\S+", re.I), r"\1" + _MASK),
    # key / key-string / authentication-key / message-digest-key [n] [md5] [타입] <값>, crypto isakmp key <값>
    (re.compile(r"(\b(?:[\w-]*-)?key(?:-string)?(?:\s+\d{1,3})?(?:\s+md5)?(?:\s+\d)?\s+)(?!generate\b|zeroize\b|chain\b|config-key\b|pubkey|storage\b|export\b|import\b|decrypt\b|encrypt\b|rsa\b|ec\b)\S+", re.I), r"\1" + _MASK),
]


def mask_secrets(text: str) -> str:
    """설정 발췌 텍스트에서 비밀번호·community·키 값을 <masked> 로 바꾼다(줄 단위)."""
    if not text:
        return text
    out = []
    for line in str(text).split("\n"):
        for pat, repl in _SECRET_PATTERNS:
            line = pat.sub(repl, line)
        out.append(line)
    return "\n".join(out)


def gen_secret(length: int = 16) -> str:
    """fixes/cisco_ios/N-xx.py 가 조치 명령어 스크립트에 쓸 임의의 강력한 문자열을 생성한다
    (D-01/WEB-02 의 "모르는 값은 무작위로 새로 설정" 원칙과 동일 - 단, 이 카테고리는 실제 장비에
    적용하지 않고 사람이 검토할 스크립트 파일에만 담기므로 값 자체를 파일에 남겨도 된다)."""
    alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits
    while True:
        s = "".join(secrets.choice(alphabet) for _ in range(length))
        if (any(c.isupper() for c in s) and any(c.islower() for c in s) and any(c.isdigit() for c in s)):
            return s + secrets.choice("!@#$%")
