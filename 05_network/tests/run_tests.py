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
]


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

    failures = []
    for code, expected_status in expected.items():
        actual_status = actual.get(code)
        if actual_status != expected_status:
            failures.append(f"{fixture_file}: {code} 기대={expected_status} 실제={actual_status}")
    missing = set(expected) - set(actual)
    for code in missing:
        failures.append(f"{fixture_file}: {code} 가 결과에 없음(check 파일 누락/예외?)")
    return failures


def main() -> None:
    all_failures = []
    for fixture_file, expected_file in CASES:
        failures = run_one(fixture_file, expected_file)
        if failures:
            all_failures.extend(failures)
        else:
            print(f"PASS: {fixture_file}")

    if all_failures:
        print(f"\nFAIL: {len(all_failures)}건 불일치")
        for f in all_failures:
            print(f"  - {f}")
        sys.exit(1)
    print("\n모든 픽스처 PASS")


if __name__ == "__main__":
    main()
