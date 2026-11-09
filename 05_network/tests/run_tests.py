#!/usr/bin/env python3
"""05_network/tests/run_tests.py — Cisco IOS 픽스처 회귀 테스트 (분석자 PC/CI 전용).

"실제 장비 출력을 검증한 것이 아니라 실제 Cisco IOS 문법에
맞게 작성한 대표 입력값으로 판정 로직을 단위 테스트한 것" 수준의 테스트를 영구 픽스처로 고정한다.
지금까지는 세션 중 임시로만 만들고 버렸던 vuln/hardened 두 running-config를 fixtures/ 에
커밋해두고, 각 항목의 "기대 판정"을 expected_<tag>.json 과 비교한다 - run.py 출력이 하나라도
달라지면(회귀) 비정상 종료해 CI가 잡아낸다.

1.4.0: fixtures/cases/cases.json 의 항목별 케이스(양호/취약 양방향)를 전부 실행하고, 모든 VULN 케이스와 전역 취약
픽스처에 대해 fix.py 조치 스크립트를 설정 텍스트에 적용한 뒤 재진단해 GOOD(문서화된 예외는 MANUAL)을 요구한다.

사용법: python tests/run_tests.py  (exit 0 = 전부 일치, exit 1 = 불일치 있음)
"""
from __future__ import annotations

import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
NETWORK_DIR = os.path.dirname(TESTS_DIR)
FIXTURES_DIR = os.path.join(TESTS_DIR, "fixtures")

CASES = [
    ("cisco_ios_vuln.txt", "expected_vuln.json"),
    ("cisco_ios_hardened.txt", "expected_hardened.json"),
    # 경계 사례(진단 검수 D-R4/D-R10/D-R11): 비밀값이 결과물에 남지 않는지, view/ipv6 community·이름 ACL·
    # no login VTY·tftp alias 판정. expected 는 해당 항목만 담는다.
    ("cisco_ios_edge.txt", "expected_edge.json"),
]

# 결과 폴더의 어떤 파일(result.json·raw·report.html·result.csv·summary)에도 나오면 안 되는 비밀값 원문(S5).
# vuln 픽스처의 community(public 은 기본값이라 검사하지 않음)·VTY 평문 비밀번호, edge 픽스처의 모든 비밀값.
SECRETS = {
    "cisco_ios_vuln.txt": ["private2024", "telnetpass", "cisco123"],
    "cisco_ios_hardened.txt": ["K9x$mPz2qLw8", "StrongPass9!", "StrongAdmin9!"],
    "cisco_ios_edge.txt": [
        "EdgeEnableHashLeak01", "EdgeUserT7", "EdgeAuditSecretLeak02", "EdgeOspfKeyLeak03",
        "EdgeTacacsKeyLeak04", "EdgeIsakmpKeyLeak05", "EdgeV13w#Comm06", "EdgeIpv6#Comm07",
        "EdgeAuthKeyLeak08", "EdgePrivKeyLeak09", "EdgeTrapCommLeak10", "EdgeTrapCommLeak11",
        "EdgeVtyPassT7Leak12", "EdgeVtyPlainLeak13", "EdgeVrfCommLeak14", "EdgeVrfCommLeak15",
    ],
}


def _secret_leaks(fixture_file: str, out_dir: str) -> list[str]:
    leaks = []
    for root, _dirs, files in os.walk(out_dir):
        for name in files:
            p = os.path.join(root, name)
            with open(p, encoding="utf-8", errors="replace") as f:
                text = f.read()
            for s in SECRETS.get(fixture_file, []):
                # result.json 은 "</" 만 이스케이프하므로 원문 그대로 검색하면 된다.
                if s in text:
                    leaks.append(f"{fixture_file}: 비밀값 '{s}' 가 결과물 {os.path.relpath(p, out_dir)} 에 남음")
    return leaks


def run_one(fixture_file: str, expected_file: str) -> list[str]:
    fixture_path = os.path.join(FIXTURES_DIR, fixture_file)
    expected_path = os.path.join(FIXTURES_DIR, expected_file)
    with open(expected_path, encoding="utf-8") as f:
        expected = json.load(f)

    with tempfile.TemporaryDirectory() as out_dir:
        proc = subprocess.run(
            [sys.executable, os.path.join(NETWORK_DIR, "run.py"), "-f", fixture_path, "-e", "cisco_ios", "-o", out_dir],
            capture_output=True, text=True, encoding="utf-8",
        )
        if proc.returncode != 0:
            return [f"{fixture_file}: run.py 가 비정상 종료함 (exit {proc.returncode})\n{proc.stderr}"]

        result_paths = glob.glob(os.path.join(out_dir, "*", "result.json"))
        if not result_paths:
            return [f"{fixture_file}: result.json 을 찾지 못함"]
        with open(result_paths[0], encoding="utf-8") as f:
            result = json.load(f)
        actual = {it["code"]: it["status"] for it in result["items"]}
        leaks = _secret_leaks(fixture_file, out_dir)

    failures = list(leaks)
    for code, expected_status in expected.items():
        actual_status = actual.get(code)
        if actual_status != expected_status:
            failures.append(f"{fixture_file}: {code} 기대={expected_status} 실제={actual_status}")
    missing = set(expected) - set(actual)
    for code in missing:
        failures.append(f"{fixture_file}: {code} 가 결과에 없음(check 파일 누락/예외?)")
    return failures


def _run_py(fixture_path: str, out_dir: str, items: str) -> dict:
    proc = subprocess.run(
        [sys.executable, os.path.join(NETWORK_DIR, "run.py"), "-f", fixture_path, "-e", "cisco_ios", "-o", out_dir, "-i", items],
        capture_output=True, text=True, encoding="utf-8",
    )
    paths = glob.glob(os.path.join(out_dir, "*", "result.json"))
    if proc.returncode != 0 or not paths:
        raise RuntimeError(f"run.py 실패 (exit {proc.returncode}) {proc.stderr}")
    return {"path": paths[0], "status": {it["code"]: it["status"] for it in json.load(open(paths[0], encoding="utf-8"))["items"]}}


# ---- 조치 스크립트 적용 시뮬레이터 -------------------------------------------------------------------------
# 장비 대신 running-config 텍스트에 IOS 명령을 순서대로 반영한다. 완전한 IOS 구현이 아니라 fixes/ 가 만드는 명령
# 형태(최상위 명령, interface/line 하위 명령 + exit, no 명령, 여러 줄 banner)만 다룬다. 다루지 못하는 형태를
# 조용히 넘기지 않도록 placeholder 가 남은 명령은 예외로 실패시킨다.
_PLACEHOLDERS = [
    (re.compile(r"<[^<>]*(?:대역|IP)[^<>]*> <wildcard mask>"), "10.1.1.0 0.0.0.255"),
    (re.compile(r"<[^<>]*IP[^<>]*>"), "10.1.1.100"),
    (re.compile(r"<[^<>]*도메인[^<>]*>"), "example.local"),
]
_BLOCK_HDR = re.compile(r"^(interface|line|router|ip access-list (?:standard|extended)) \S")
# 하위 명령 중 같은 종류가 한 줄만 존재하는 것(새 값이 옛 값을 대체) - 키는 첫 토큰
_SUB_SINGLE = {"exec-timeout", "login", "password", "access-class", "exec", "session-timeout"}
# 최상위 명령 중 같은 접두어가 한 줄만 존재하는 것
_TOP_SINGLE = ("security passwords min-length", "login block-for", "logging buffered", "logging trap", "logging console",
               "ip ssh version", "ip domain-name", "service timestamps log", "enable secret", "hostname")
# no 명령을 넣어도 running-config 에 "no ..." 줄이 남지 않는 것(지우기만 함)
_NO_SILENT = ("snmp-server community", "access-list", "username", "logging host", "ntp server", "banner")


class UnappliedCommand(Exception):
    pass


def _end_idx(lines: list[str]) -> int:
    return max(i for i, l in enumerate(lines) if l.strip() == "end")


def _block_range(lines: list[str], hdr: str) -> tuple[int, int] | None:
    for i, l in enumerate(lines):
        if l.rstrip() == hdr:
            j = i + 1
            while j < len(lines) and lines[j].startswith(" "):
                j += 1
            return i, j
    return None


def _remove_banner(lines: list[str], kind: str) -> list[str]:
    out, i = [], 0
    while i < len(lines):
        m = re.match(rf"^banner {kind}[ \t]+(\S.*)$", lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        rest = m.group(1)
        delim = "^C" if rest.startswith("^C") else rest[0]
        if delim in rest[len(delim):]:
            i += 1
            continue
        i += 1
        while i < len(lines) and delim not in lines[i]:
            i += 1
        i += 1
    return out


def _sub_key(cmd: str) -> tuple:
    t = cmd.split()
    if t[0] in _SUB_SINGLE:
        return (t[0],)
    if t[:2] == ["ip", "access-group"]:
        return ("ip", "access-group", t[-1])
    return tuple(t[:2])


def _apply_sub(lines: list[str], hdr: str, cmd: str) -> None:
    s, e = _block_range(lines, hdr)
    children = [c.strip() for c in lines[s + 1:e]]
    if cmd.startswith("no "):
        x = cmd[3:]
        children = [c for c in children if c != x and not c.startswith(x + " ") and c != cmd]
        children.append(cmd)
    else:
        k = _sub_key(cmd)
        children = [c for c in children if c != "no " + cmd and _sub_key(c) != k]
        children.append(cmd)
    lines[s + 1:e] = [" " + c for c in children]


def _apply_top(lines: list[str], cmd: str) -> list[str]:
    if cmd.startswith("no "):
        x = cmd[3:]
        if x.startswith("banner "):
            return _remove_banner(lines, x.split()[1])
        lines = [l for l in lines if l.startswith(" ") or (l.rstrip() != x and not l.startswith(x + " "))]
        if not x.startswith(_NO_SILENT) and cmd not in lines:
            lines.insert(_end_idx(lines), cmd)
        return lines
    lines = [l for l in lines if l.rstrip() != "no " + cmd]
    for p in _TOP_SINGLE:
        if cmd.startswith(p):
            lines = [l for l in lines if not l.startswith(p)]
    if cmd not in lines:
        lines.insert(_end_idx(lines), cmd)
    return lines


def _apply_remediation(config: str, remediation: str) -> str:
    """생성된 조치 스크립트(configure terminal ~ end)를 설정 텍스트에 순서대로 적용해 본다(장비 대신)."""
    lines = config.splitlines()
    body = remediation.split("configure terminal", 1)[1].split("\nend\n", 1)[0].splitlines()
    hdr = None
    i = 0
    while i < len(body):
        cmd = body[i].strip()
        i += 1
        if not cmd or cmd.startswith("!"):
            continue
        for pat, val in _PLACEHOLDERS:
            cmd = pat.sub(val, cmd)
        if "<" in cmd and ">" in cmd:
            raise UnappliedCommand(f"placeholder 를 바꾸지 못한 명령: {cmd}")
        m = re.match(r"^banner (motd|login|exec|incoming) (\S+)(.*)$", cmd)
        if m:
            kind, delim, rest = m.group(1), m.group(2), m.group(3)
            if delim.startswith("^C"):
                delim = "^C"
            block = [f"banner {kind} {delim}{rest}"]
            if delim not in rest:
                while i < len(body) and delim not in body[i]:
                    block.append(body[i])
                    i += 1
                if i >= len(body):
                    raise UnappliedCommand(f"banner {kind} 구분자 {delim} 가 닫히지 않음")
                block.append(body[i])
                i += 1
            lines = _remove_banner(lines, kind)
            idx = _end_idx(lines)
            lines[idx:idx] = block
            hdr = None
            continue
        if cmd == "exit":
            hdr = None
            continue
        if _BLOCK_HDR.match(cmd):
            hdr = cmd
            if _block_range(lines, hdr) is None:
                lines.insert(_end_idx(lines), hdr)
            continue
        if hdr:
            _apply_sub(lines, hdr, cmd)
        else:
            lines = _apply_top(lines, cmd)
    return "\n".join(lines) + "\n"


def run_snmp_fix_case() -> list[str]:
    """조치 후속 F-R7: view·ipv6 토큰이 있는 community 줄도 N-18/19/20 조치 명령이 만들어지고(수동 안내로 빠지지
    않고), 생성된 스크립트를 순서대로 적용하면 세 항목 모두 GOOD 이 되며 view·ipv6 ACL 이 유지되는지 확인한다."""
    fixture = os.path.join(FIXTURES_DIR, "cisco_ios_snmp_fix.txt")
    codes = ["N-18", "N-19", "N-20"]
    label = "cisco_ios_snmp_fix.txt(조치)"
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        before = _run_py(fixture, os.path.join(tmp, "before"), ",".join(codes))
        for c in codes:
            if before["status"].get(c) != "VULN":
                failures.append(f"{label}: 조치 전 {c} 기대=VULN 실제={before['status'].get(c)}")
        proc = subprocess.run(
            [sys.executable, os.path.join(NETWORK_DIR, "fix.py"), "-f", fixture, "-r", before["path"], "-o", os.path.join(tmp, "fix")],
            capture_output=True, text=True, encoding="utf-8",
        )
        rem_paths = glob.glob(os.path.join(tmp, "fix", "*", "remediation_*.txt"))
        if proc.returncode != 0 or not rem_paths:
            return failures + [f"{label}: fix.py 실패 (exit {proc.returncode}) {proc.stderr}"]
        remediation = open(rem_paths[0], encoding="utf-8").read()
        body = remediation.split("configure terminal", 1)[-1]  # 머리말 안내문에도 "[수동 조치 필요]" 문구가 있다
        if "[수동 조치 필요]" in body or "[오류]" in body:
            failures.append(f"{label}: 조치 명령 대신 수동 안내/오류가 나옴")
        with open(fixture, encoding="utf-8") as f:
            fixed = _apply_remediation(f.read(), remediation)
        fixed_path = os.path.join(tmp, "fixed.txt")
        with open(fixed_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(fixed)
        after = _run_py(fixed_path, os.path.join(tmp, "after"), ",".join(codes))
        for c in codes:
            if after["status"].get(c) != "GOOD":
                failures.append(f"{label}: 조치 적용 후 {c} 기대=GOOD 실제={after['status'].get(c)}")
        comm = [l for l in fixed.splitlines() if l.startswith("snmp-server community ")]
        for want in ("Fx7#ViewComm01 view v1 RO 20", "Fx7#Ipv6Comm02 RO ipv6 V6ACL 10", "Fx7#Ipv6Comm03 RO ipv6 V6ACL 20"):
            if f"snmp-server community {want}" not in comm:
                failures.append(f"{label}: 재발급 줄에 '{want}' 가 없음(view/ipv6 유실?)")
        if not any(" view v2 RO 20" in l and " weak " not in l for l in comm):
            failures.append(f"{label}: 약한 문자열(view v2) 줄이 새 문자열·view·ACL 로 재발급되지 않음")
        if len(comm) != 4:
            failures.append(f"{label}: 조치 후 community 줄 수 기대=4 실제={len(comm)}")
    return failures


CASES_DIR = os.path.join(FIXTURES_DIR, "cases")

# 조치 스크립트를 적용한 뒤에도 GOOD 이 될 수 없는(사람 판단·위치 확인이 남는) 항목과 그때의 기대 상태.
AFTER_FIX_EXPECT = {
    "N-02": ("MANUAL", "min-length 를 넣어도 값이 기관 비밀번호 정책에 맞는지는 사람이 확인(가이드 양호 기준이 기관 정책)"),
    "N-14": ("MANUAL", "로깅 설정을 넣어도 기관 로그 기록 정책에 맞는지는 사람이 확인(가이드 양호 기준이 정책)"),
    "N-22": ("MANUAL", "ACL 정의만 생성하고 경계 인터페이스 적용(ip access-group in)은 위치 확인 후 사람이 입력(주석 예시)"),
}


def _case_file(c: dict) -> str:
    return c.get("file") or f"{c['code']}_{c['name']}.txt"


def load_cases() -> list[dict]:
    path = os.path.join(CASES_DIR, "cases.json")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def run_cases(cases: list[dict]) -> list[str]:
    """tests/fixtures/cases/cases.json 의 항목별 케이스를 전부 실행한다. 케이스 파일이 없거나 결과가 다르면 실패,
    cases.json 에 없는 케이스 파일(orphan)도 실패 - 커버리지 판정기(lib/tests/coverage.py)가 세는 선언과 실제 실행을 맞춘다."""
    failures = []
    listed = set()
    with tempfile.TemporaryDirectory() as tmp:
        for n, c in enumerate(cases):
            fn = _case_file(c)
            listed.add(fn)
            if c.get("engine", "cisco_ios") != "cisco_ios":
                failures.append(f"cases/{fn}: 지원하지 않는 engine {c.get('engine')}")
                continue
            path = os.path.join(CASES_DIR, fn)
            if not os.path.isfile(path):
                failures.append(f"cases/{fn}: 케이스 파일 없음")
                continue
            try:
                got = _run_py(path, os.path.join(tmp, str(n)), c["code"])["status"].get(c["code"])
            except RuntimeError as e:
                failures.append(f"cases/{fn}: {e}")
                continue
            if got != c["expect"]:
                failures.append(f"cases/{fn}: {c['code']} 기대={c['expect']} 실제={got}")
    for fn in sorted(os.listdir(CASES_DIR)) if os.path.isdir(CASES_DIR) else []:
        if fn.endswith(".txt") and fn not in listed:
            failures.append(f"cases/{fn}: cases.json 에 등록되지 않은 케이스 파일")
    return failures


def _fix_and_recheck(fixture: str, codes: list[str] | None, tmp: str, label: str) -> list[str]:
    """fixture 를 진단 → fix.py 로 조치 스크립트 생성 → 시뮬레이터로 적용 → 재진단. 조치 전 VULN 이던 항목은
    GOOD(또는 AFTER_FIX_EXPECT 의 문서화된 상태)이어야 한다."""
    items = ",".join(codes) if codes else None
    def run(path, out):
        if items:
            return _run_py(path, out, items)
        proc = subprocess.run([sys.executable, os.path.join(NETWORK_DIR, "run.py"), "-f", path, "-e", "cisco_ios", "-o", out],
                              capture_output=True, text=True, encoding="utf-8")
        paths = glob.glob(os.path.join(out, "*", "result.json"))
        if proc.returncode != 0 or not paths:
            raise RuntimeError(f"run.py 실패 (exit {proc.returncode}) {proc.stderr}")
        return {"path": paths[0], "status": {it["code"]: it["status"] for it in json.load(open(paths[0], encoding="utf-8"))["items"]}}

    before = run(fixture, os.path.join(tmp, "before"))
    vulns = sorted(c for c, s in before["status"].items() if s == "VULN")
    if not vulns:
        return [f"{label}: 조치 전 VULN 항목이 없음(케이스가 취약 상태가 아님)"]
    proc = subprocess.run(
        [sys.executable, os.path.join(NETWORK_DIR, "fix.py"), "-f", fixture, "-r", before["path"], "-o", os.path.join(tmp, "fix")]
        + (["-i", items] if items else []),
        capture_output=True, text=True, encoding="utf-8",
    )
    rem_paths = glob.glob(os.path.join(tmp, "fix", "*", "remediation_*.txt"))
    if proc.returncode != 0 or not rem_paths:
        return [f"{label}: fix.py 실패 (exit {proc.returncode}) {proc.stderr}"]
    remediation = open(rem_paths[0], encoding="utf-8").read()
    failures = []
    if "[오류]" in remediation:
        failures.append(f"{label}: 조치 명령 생성 중 예외")
    with open(fixture, encoding="utf-8") as f:
        try:
            fixed = _apply_remediation(f.read(), remediation)
        except UnappliedCommand as e:
            return failures + [f"{label}: {e}"]
    fixed_path = os.path.join(tmp, "fixed.txt")
    with open(fixed_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(fixed)
    after = run(fixed_path, os.path.join(tmp, "after"))
    for c in vulns:
        want = AFTER_FIX_EXPECT.get(c, ("GOOD", ""))[0]
        if after["status"].get(c) != want:
            failures.append(f"{label}: 조치 적용 후 {c} 기대={want} 실제={after['status'].get(c)}")
    return failures


def run_fix_cases(cases: list[dict]) -> tuple[list[str], int]:
    """모든 VULN 케이스(cases.json) + 전역 취약 픽스처에 대해 조치 → 재진단을 확인한다."""
    failures, n = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        failures += _fix_and_recheck(os.path.join(FIXTURES_DIR, "cisco_ios_vuln.txt"), None, os.path.join(tmp, "vuln"),
                                     "cisco_ios_vuln.txt(전 항목 조치)")
        n += 1
        for k, c in enumerate(cases):
            if c["expect"] != "VULN":
                continue
            path = os.path.join(CASES_DIR, _case_file(c))
            if not os.path.isfile(path):
                continue  # run_cases 가 이미 실패로 보고
            failures += _fix_and_recheck(path, [c["code"]], os.path.join(tmp, f"c{k}"), f"cases/{_case_file(c)}(조치)")
            n += 1
    return failures, n


def _run_cli(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, os.path.join(NETWORK_DIR, "run.py")] + args,
                          capture_output=True, text=True, encoding="utf-8")


NXOS_SECRETS = ["NxAuthKeyLeak21", "NxPrivKeyLeak22", "0x1234NxAuthHexLeak23", "0x5678NxPrivHexLeak24"]


def run_cli_cases() -> list[str]:
    """진입점 동작 회귀(외부 검수 A14/B1/B5/C4)."""
    failures = []
    nxos = os.path.join(FIXTURES_DIR, "nxos_reject.txt")
    vuln = os.path.join(FIXTURES_DIR, "cisco_ios_vuln.txt")
    with tempfile.TemporaryDirectory() as tmp:
        # A14: NX-OS 설정은 자동 판별·-e cisco_ios 강제 모두 거부(0 아닌 종료, 결과물 없음), 비밀값은 어디에도 안 남음
        for label, extra in (("자동 판별", []), ("-e cisco_ios 강제", ["-e", "cisco_ios"])):
            out = os.path.join(tmp, f"nx{len(extra)}")
            p = _run_cli(["-f", nxos, "-o", out] + extra)
            if p.returncode == 0:
                failures.append(f"nxos_reject.txt({label}): NX-OS 설정인데 exit 0")
            if glob.glob(os.path.join(out, "*", "result.json")):
                failures.append(f"nxos_reject.txt({label}): NX-OS 설정을 IOS 로 판정해 결과물을 만듦")
            for s in NXOS_SECRETS:
                if s in p.stdout + p.stderr or any(s in open(f, encoding="utf-8", errors="replace").read()
                                                   for f in glob.glob(os.path.join(out, "**", "*"), recursive=True) if os.path.isfile(f)):
                    failures.append(f"nxos_reject.txt({label}): 비밀값 '{s}' 노출")
        # A14 이중 방어: 마스킹 함수 자체도 NX-OS `priv <key>`/`priv aes-128 <key>` 를 가린다
        sys.path.insert(0, NETWORK_DIR)
        from parsers import cisco_ios as cio  # noqa: E402
        masked = cio.mask_secrets(open(nxos, encoding="utf-8").read())
        for s in NXOS_SECRETS:
            if s in masked:
                failures.append(f"mask_secrets: NX-OS 비밀값 '{s}' 가 마스킹되지 않음")
        # B1: 같은 hostname 설정 2개를 -d 로 돌리면 결과 폴더 2개
        d = os.path.join(tmp, "same_host")
        os.makedirs(d)
        for n in ("a.txt", "b.txt"):
            with open(vuln, encoding="utf-8") as src, open(os.path.join(d, n), "w", encoding="utf-8", newline="\n") as dst:
                dst.write(src.read())
        out = os.path.join(tmp, "b1")
        p = _run_cli(["-d", d, "-e", "cisco_ios", "-o", out, "-i", "N-01"])
        n_res = len(glob.glob(os.path.join(out, "*", "result.json")))
        if p.returncode != 0 or n_res != 2:
            failures.append(f"-d 같은 hostname 2개: exit={p.returncode} result.json {n_res}개(기대 2) {p.stderr[-300:]}")
        # B5: 벤더 판별 실패 파일이 섞이면 나머지는 분석하되 exit 1, 없는 파일도 exit 1
        with open(os.path.join(d, "c_unknown.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write("this is not a device config\n")
        out = os.path.join(tmp, "b5")
        p = _run_cli(["-d", d, "-o", out, "-i", "N-01"])
        n_res = len(glob.glob(os.path.join(out, "*", "result.json")))
        if p.returncode == 0 or n_res != 2:
            failures.append(f"-d 판별 실패 파일 포함: exit={p.returncode}(기대 0 아님) result.json {n_res}개(기대 2)")
        p = _run_cli(["-f", os.path.join(tmp, "no_such_file.txt"), "-o", os.path.join(tmp, "b5b")])
        if p.returncode == 0:
            failures.append("-f 없는 파일: exit 0(기대 0 아님)")
        # C4: -e 와 하위 호환 -v 모두 동작
        for opt in ("-e", "-v", "--engine", "--vendor"):
            out = os.path.join(tmp, "c4" + opt.strip("-"))
            p = _run_cli(["-f", vuln, opt, "cisco_ios", "-o", out, "-i", "N-01"])
            if p.returncode != 0 or not glob.glob(os.path.join(out, "*", "result.json")):
                failures.append(f"벤더 지정 옵션 {opt}: 동작하지 않음 (exit {p.returncode}) {p.stderr[-200:]}")
    return failures


POLICY_HEAD = "# 테스트 정책\ncategory=05\nexpires=2999-12-31\napprover=승인자A\n"


def _fix_cli(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, os.path.join(NETWORK_DIR, "fix.py")] + args,
                          capture_output=True, text=True, encoding="utf-8")


def run_policy_cases() -> list[str]:
    """1.6.0 G-06: fix.py --policy/--operator. 정책 승인 항목만 명령어를 만들고, 미승인·호스트 제외·irreversible 플래그
    없음은 사유와 함께 제외 목록(remediation 머리말·fix.log POLICY_SKIPPED·표준 출력)으로 남기며, 정책 거부는 exit 2 로
    아무것도 만들지 않는다. audit.txt 에 G-03 감사 키를 남긴다."""
    failures = []
    vuln = os.path.join(FIXTURES_DIR, "cisco_ios_vuln.txt")
    with tempfile.TemporaryDirectory() as tmp:
        before = _run_py(vuln, os.path.join(tmp, "run"), "N-08,N-16,N-26,N-30,N-37,N-02,N-36")
        host = json.load(open(before["path"], encoding="utf-8"))["host"]

        def pol(name: str, text: str) -> str:
            p = os.path.join(tmp, name)
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            return p

        def fix(label: str, extra: list[str]) -> tuple[subprocess.CompletedProcess, str]:
            out = os.path.join(tmp, "o_" + label)
            return _fix_cli(["-f", vuln, "-r", before["path"], "-o", out] + extra), out

        # ---- 정상: 승인(N-16 영향 없음, N-08:irreversible, N-36) / irreversible 없음(N-26) / 호스트 제외(N-37) / 미승인(N-02,N-30)
        p_ok = pol("ok.txt", POLICY_HEAD + "N-16\nN-08:irreversible\nN-26\nN-37\nN-36\n"
                   f"[host:{host.upper()}]\n-N-37\n[host:*]\n-N-16\n")
        proc, out = fix("ok", ["--policy", p_ok, "--operator", "운영자B"])
        label = "정책 모드(정상)"
        rem = glob.glob(os.path.join(out, "*", "remediation_*.txt"))
        aud = glob.glob(os.path.join(out, "*", "audit.txt"))
        log = glob.glob(os.path.join(out, "*", "fix.log"))
        if proc.returncode != 0 or not rem or not aud or not log:
            return [f"{label}: exit {proc.returncode}, remediation {len(rem)} audit {len(aud)} fix.log {len(log)} {proc.stderr[-300:]}"]
        text = open(rem[0], encoding="utf-8").read()
        body = text.split("configure terminal", 1)[1]
        for want in ("service timestamps log", "transport input ssh", "no ip domain-lookup"):
            if want not in body:
                failures.append(f"{label}: 승인 항목 명령 '{want}' 없음")
        for unwanted, why in (("no service finger", "N-26 irreversible 없음"), ("no service pad", "N-37 호스트 제외"),
                              ("security passwords", "N-02 미승인"), ("no cdp run", "N-30 미승인")):
            if unwanted in body:
                failures.append(f"{label}: 제외돼야 할 명령 '{unwanted}' 이 들어감({why})")
        head = text.split("configure terminal", 1)[0]
        log_text = open(log[0], encoding="utf-8").read()
        for code, reason in (("N-26", "irreversible 플래그 필요: 영향: "), ("N-37", f"정책 미승인(호스트 제외: [host:{host.upper()}])"),
                             ("N-02", "정책 미승인"), ("N-30", "정책 미승인")):
            if f"!   {code}: {reason}" not in head:
                failures.append(f"{label}: remediation 제외 목록에 '{code}: {reason}' 없음")
            if f"POLICY_SKIPPED {code} {reason}" not in log_text:
                failures.append(f"{label}: fix.log 에 'POLICY_SKIPPED {code} {reason}' 없음")
            if f"{code}: {reason}" not in proc.stdout:
                failures.append(f"{label}: 표준 출력 제외 목록에 {code} 없음")
        audit = dict(ln.split("=", 1) for ln in open(aud[0], encoding="utf-8").read().splitlines() if "=" in ln)
        want_keys = ["operator", "login_user", "approver", "policy_file", "policy_sha256", "policy_expires", "started_at",
                     "host", "category", "mode", "finished_at", "applied", "failed", "declined", "skipped", "manual",
                     "preview", "policy_skipped", "failed_codes"]
        missing = [k for k in want_keys if k not in audit]
        if missing:
            failures.append(f"{label}: audit.txt 키 누락 {missing}")
        exp = {"operator": "운영자B", "approver": "승인자A", "host": host, "category": "05", "mode": "apply",
               "policy_expires": "2999-12-31", "policy_file": os.path.abspath(p_ok), "applied": "3", "policy_skipped": "4", "failed": "0",
               "skipped": "0", "declined": "0", "preview": "0", "manual": "0", "failed_codes": "",
               "policy_sha256": hashlib.sha256(open(p_ok, "rb").read()).hexdigest()}
        for k, v in exp.items():
            if audit.get(k) != v:
                failures.append(f"{label}: audit.txt {k} 기대={v} 실제={audit.get(k)}")
        if not log_text.startswith("operator=운영자B\n"):
            failures.append(f"{label}: fix.log 맨 앞에 감사 머리 줄이 없음")

        # ---- [host:*] 만 맞는 경우: -N-16 제외
        p_star = pol("star.txt", POLICY_HEAD + "N-16\nN-36\n[host:other]\n-N-36\n[host:*]\n-N-16\n")
        proc, out = fix("star", ["--policy", p_star, "--operator", "op"])
        rem = glob.glob(os.path.join(out, "*", "remediation_*.txt"))
        if proc.returncode != 0 or not rem:
            failures.append(f"[host:*] 정책: exit {proc.returncode} {proc.stderr[-200:]}")
        else:
            body = open(rem[0], encoding="utf-8").read().split("configure terminal", 1)[1]
            if "no ip domain-lookup" not in body or "service timestamps log" in body:
                failures.append("[host:*] 정책: N-36 만 들어가야 함([host:other] 의 제외는 적용 안 됨, [host:*] 의 -N-16 적용)")

        # ---- 승인 항목이 모두 빠지면 remediation 없이 audit.txt 만, exit 0
        p_none = pol("none.txt", POLICY_HEAD + "N-26\n[host:*]\n")
        proc, out = fix("none", ["--policy", p_none, "--operator", "op"])
        if proc.returncode != 0 or glob.glob(os.path.join(out, "*", "remediation_*.txt")) \
                or not glob.glob(os.path.join(out, "*", "audit.txt")):
            failures.append(f"승인 0건 정책: exit {proc.returncode}, remediation 없고 audit.txt 만 있어야 함")

        # ---- 거부(exit 2, 결과물 없음)
        exp_old = POLICY_HEAD.replace("2999-12-31", "2000-01-01")
        bad = [
            ("operator 없음", ["--policy", p_ok], "--operator"),
            ("operator 비어 있음", ["--policy", p_ok, "--operator", "  "], "--operator"),
            ("operator 제어 문자", ["--policy", p_ok, "--operator", "op\x1bx"], "제어 문자"),
            ("operator 단독", ["--operator", "op"], "--policy"),
            ("category 불일치", ["--policy", pol("cat.txt", POLICY_HEAD.replace("=05", "=01") + "N-16\n[host:*]\n"),
                                 "--operator", "op"], "카테고리 불일치"),
            ("유효기간 경과", ["--policy", pol("exp.txt", exp_old + "N-16\n[host:*]\n"), "--operator", "op"], "유효기간 경과"),
            ("없는 코드", ["--policy", pol("code.txt", POLICY_HEAD + "N-16\nU-01\n[host:*]\n"), "--operator", "op"], "없는 코드"),
            ("코드 중복", ["--policy", pol("dup.txt", POLICY_HEAD + "N-16\nN-16\n[host:*]\n"), "--operator", "op"], "중복"),
            ("알 수 없는 키", ["--policy", pol("key.txt", POLICY_HEAD + "mode=auto\nN-16\n[host:*]\n"), "--operator", "op"],
             "알 수 없는 키"),
            ("호스트 미등록", ["--policy", pol("host.txt", POLICY_HEAD + "N-16\n[host:other]\n"), "--operator", "op"],
             "정책에 없는 호스트"),
            ("정책 파일 없음", ["--policy", os.path.join(tmp, "nofile.txt"), "--operator", "op"], "정책 파일"),
        ]
        for i, (name, extra, want) in enumerate(bad):
            proc, out = fix(f"bad{i}", extra)
            if proc.returncode != 2:
                failures.append(f"정책 거부({name}): exit {proc.returncode}(기대 2)")
            if want not in proc.stderr:
                failures.append(f"정책 거부({name}): 오류 메시지에 '{want}' 없음: {proc.stderr.strip()[-200:]}")
            if os.path.exists(out) and os.listdir(out):
                failures.append(f"정책 거부({name}): 결과물을 만듦 {os.listdir(out)}")
        # 형식 오류 줄 번호
        proc, _ = fix("lineno", ["--policy", pol("ln.txt", POLICY_HEAD + "N-16\n[host:*]\nN-36\n"), "--operator", "op"])
        if proc.returncode != 2 or "7행:" not in proc.stderr:
            failures.append(f"정책 형식 오류 줄 번호: exit {proc.returncode} {proc.stderr.strip()[-200:]}")

        # ---- 정책 없는 모드는 그대로(영향 머리말이 있어도 전부 생성, audit.txt 없음)
        proc, out = fix("nopolicy", [])
        rem = glob.glob(os.path.join(out, "*", "remediation_*.txt"))
        if proc.returncode != 0 or not rem or glob.glob(os.path.join(out, "*", "audit.txt")):
            failures.append(f"정책 없는 모드: exit {proc.returncode}, remediation {len(rem)}")
        elif "no service finger" not in open(rem[0], encoding="utf-8").read():
            failures.append("정책 없는 모드: 영향 머리말 항목(N-26)까지 생성돼야 함")

    # 정책 파서 단위 테스트(lib/tests/fix_policy_test.py)도 이 진입점(CI network job)에서 같이 돈다
    proc = subprocess.run([sys.executable, os.path.join(os.path.dirname(NETWORK_DIR), "lib", "tests", "fix_policy_test.py")],
                          capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        failures.append(f"lib/tests/fix_policy_test.py 실패:\n{proc.stdout}{proc.stderr}")
    else:
        print(proc.stdout.strip())
    return failures


def main() -> None:
    all_failures = []
    failures = run_policy_cases()
    if failures:
        all_failures.extend(failures)
    else:
        print("PASS: 조치 정책 모드(승인·제외 사유·irreversible·[host:*]·감사 기록·거부 exit 2)")
    failures = run_cli_cases()
    if failures:
        all_failures.extend(failures)
    else:
        print("PASS: 진입점(NX-OS 거부·마스킹, -d 같은 hostname, 실패 시 exit 1, -e/-v)")
    for fixture_file, expected_file in CASES:
        failures = run_one(fixture_file, expected_file)
        if failures:
            all_failures.extend(failures)
        else:
            print(f"PASS: {fixture_file}")
    failures = run_snmp_fix_case()
    if failures:
        all_failures.extend(failures)
    else:
        print("PASS: cisco_ios_snmp_fix.txt (N-18/19/20 조치 명령 적용 후 GOOD, view/ipv6 유지)")

    cases = load_cases()
    failures = run_cases(cases)
    if failures:
        all_failures.extend(failures)
    else:
        print(f"PASS: 항목별 케이스 {len(cases)}건 (cases/cases.json)")
    failures, n = run_fix_cases(cases)
    if failures:
        all_failures.extend(failures)
    else:
        print(f"PASS: 조치 적용 후 재진단 {n}건 (VULN → GOOD, 문서화된 예외 {sorted(AFTER_FIX_EXPECT)} 는 MANUAL)")

    if all_failures:
        print(f"\nFAIL: {len(all_failures)}건 불일치")
        for f in all_failures:
            print(f"  - {f}")
        sys.exit(1)
    print("\n모든 픽스처 PASS")


if __name__ == "__main__":
    main()
