#!/usr/bin/env python3
"""05_network/tests/run_tests.py — Cisco IOS 픽스처 회귀 테스트 (분석자 PC/CI 전용).

05_network/CLAUDE.md가 예고해둔 "실제 장비 출력을 검증한 것이 아니라 실제 Cisco IOS 문법에
맞게 작성한 대표 입력값으로 판정 로직을 단위 테스트한 것" 수준의 테스트를 영구 픽스처로 고정한다.
지금까지는 세션 중 임시로만 만들고 버렸던 vuln/hardened 두 running-config를 fixtures/ 에
커밋해두고, 각 항목의 "기대 판정"을 expected_<tag>.json 과 비교한다 - run.py 출력이 하나라도
달라지면(회귀) 비정상 종료해 CI가 잡아낸다.

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


def _apply_remediation(config: str, remediation: str) -> str:
    """생성된 조치 스크립트를 설정 텍스트에 순서대로 적용해 본다(장비 대신). `no snmp-server community X` 는 그
    community 줄을 지우고, 나머지 명령 줄은 placeholder 를 실제 값으로 바꿔 end 앞에 덧붙인다."""
    lines = config.splitlines()
    body = remediation.split("configure terminal", 1)[1].split("\nend\n", 1)[0]
    for cmd in body.splitlines():
        cmd = cmd.strip()
        if not cmd or cmd.startswith("!"):
            continue
        m = re.match(r"^no snmp-server community (\S+)$", cmd)
        if m:
            lines = [l for l in lines if l.split()[:3] != ["snmp-server", "community", m.group(1)]]
            continue
        cmd = cmd.replace("<관리-시스템-IP> <wildcard mask>", "10.1.1.0 0.0.0.255")
        idx = max(i for i, l in enumerate(lines) if l.strip() == "end")
        lines.insert(idx, cmd)
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

    if all_failures:
        print(f"\nFAIL: {len(all_failures)}건 불일치")
        for f in all_failures:
            print(f"  - {f}")
        sys.exit(1)
    print("\n모든 픽스처 PASS")


if __name__ == "__main__":
    main()
