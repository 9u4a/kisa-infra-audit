"""05_network/parsers/cisco_ios.py — Cisco IOS `show running-config` 텍스트 파싱 헬퍼.

실제 장비 없이 미리 수집된 설정 텍스트 파일만으로 판정하므로(05_network/CLAUDE.md "오프라인
설정파일 분석" 원칙), 이 모듈은 정규식/블록 파싱만 제공하고 판정 로직은 각 checks/cisco_ios/N-xx.py
에 둔다. Cisco IOS 설정에서 하위 명령은 정확히 공백 1칸으로 들여쓰기되고, 최상위 명령/`!` 구분자는
들여쓰기가 없다 — 이 규칙으로 블록(line/interface 등)을 구분한다.
"""
from __future__ import annotations

import re
import secrets
import string


def detect(text: str) -> bool:
    if re.search(r"^version \d+\.\d+", text, re.M):
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
        (물리적으로 사용 중인 L3 인터페이스만 대상으로 per-interface 항목을 판정하기 위함)."""
        out = []
        for b in self.interface_blocks:
            body = "\n".join(b)
            if re.search(r"^\s*ip address \d", body, re.M) and not re.search(r"^\s*shutdown\s*$", body, re.M):
                out.append(body)
        return out


def iface_name(block_text: str) -> str:
    """interface/line 블록(문자열, 첫 줄이 헤더)에서 이름만 추출. 예: "interface GigabitEthernet0/1" -> "GigabitEthernet0/1"."""
    first = block_text.splitlines()[0]
    parts = first.split(None, 1)
    return parts[1] if len(parts) > 1 else first


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
    # snmp-server host <addr> [informs|traps] [version 1|2c|3 [auth|noauth|priv]] <community> ...
    (re.compile(r"(\bsnmp-server\s+host\s+\S+(?:\s+(?:informs|traps))?(?:\s+version\s+(?:1|2c|3(?:\s+(?:auth|noauth|priv))?))?\s+)(?!version\b|informs\b|traps\b)\S+", re.I), r"\1<community>"),
    # SNMPv3 user: ... auth md5|sha* <key> priv des|3des|aes [128|192|256] <key>
    (re.compile(r"(\bauth\s+(?:md5|sha\S*)\s+)\S+", re.I), r"\1" + _MASK),
    (re.compile(r"(\bpriv\s+(?:des\S*|3des|aes(?:\s+\d+)?)\s+)\S+", re.I), r"\1" + _MASK),
    # password|secret [암호화 타입 숫자] <값>  (enable/username/line/ppp chap 등 공통)
    (re.compile(r"(\b(?:password|secret)(?:\s+\d{1,2})?\s+)\S+", re.I), r"\1" + _MASK),
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
