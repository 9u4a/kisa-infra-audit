#!/usr/bin/env python3
"""05_network/tests/run_tests.py — Cisco IOS 픽스처 회귀 테스트 (분석자 PC/CI 전용).

05_network/CLAUDE.md가 예고해둔 "실제 장비 출력을 검증한 것이 아니라 실제 Cisco IOS 문법에
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
        "EdgeVtyPassT7Leak12", "EdgeVtyPlainLeak13",
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
            [sys.executable, os.path.join(NETWORK_DIR, "run.py"), "-f", fixture_path, "-v", "cisco_ios", "-o", out_dir],
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
        [sys.executable, os.path.join(NETWORK_DIR, "run.py"), "-f", fixture_path, "-v", "cisco_ios", "-o", out_dir, "-i", items],
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
        proc = subprocess.run([sys.executable, os.path.join(NETWORK_DIR, "run.py"), "-f", path, "-v", "cisco_ios", "-o", out],
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


def main() -> None:
    all_failures = []
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
