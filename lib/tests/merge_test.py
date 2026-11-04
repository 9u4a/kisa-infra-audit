#!/usr/bin/env python3
"""lib/tests/merge_test.py — lib/merge.py 회귀 테스트(분석자 PC/CI 전용).

X-05(1.3.4): Windows PowerShell 5.1 의 Out-File -Encoding utf8 은 BOM 을 붙이는데, merge.py 가 utf-8 로 읽어
JSONDecodeError → "건너뜀" 경고만 내고 그 호스트를 병합 결과에서 빠뜨렸다. BOM 있는/없는 result.json 을 섞어
두 호스트가 모두 병합되는지 확인한다.
P-22(1.5.0): 같은 호스트의 이전 결과(generated_at 이 더 이른 것)는 빼고 최근 것만 병합해야 한다 - 예전에는 합산해 부풀었다.
"""
import csv
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def result(host: str, status: str, at: str = "2026-10-29T00:00:00") -> dict:
    return {"tool_version": "test", "guide_version": "2026", "category": "02_windows", "host": host, "env": "test",
            "generated_at": at, "items": [{"code": "W-01", "status": status, "detail": "d", "evidence": ""}]}


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for host, status, enc in (("win-bom", "VULN", "utf-8-sig"), ("linux-nobom", "GOOD", "utf-8")):
            d = os.path.join(tmp, f"{host}_02_20261029-000000")
            os.makedirs(d)
            p = os.path.join(d, "result.json")
            with open(p, "w", encoding=enc, newline="\n") as f:
                json.dump(result(host, status), f, ensure_ascii=False)
            paths.append(p)
        # 같은 호스트 win-bom 의 이전 진단(GOOD) - 최근 것(VULN)만 남아야 한다
        d = os.path.join(tmp, "win-bom_02_20261028-000000")
        os.makedirs(d)
        with open(os.path.join(d, "result.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(result("win-bom", "GOOD", "2026-10-28T00:00:00"), f, ensure_ascii=False)
        paths.append(os.path.join(d, "result.json"))
        out = os.path.join(tmp, "merged")
        proc = subprocess.run([sys.executable, os.path.join(ROOT, "lib", "merge.py"), *paths, "-o", out],
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
        fails = []
        if proc.returncode != 0:
            fails.append(f"merge.py 종료 코드 {proc.returncode}: {proc.stderr.strip()}")
        if "건너뜀" in proc.stderr:
            fails.append(f"건너뛴 결과 있음: {proc.stderr.strip()}")
        csv_path = os.path.join(out, "merged.csv")
        rows = []
        if os.path.isfile(csv_path):
            with open(csv_path, encoding="utf-8-sig", newline="") as f:
                rows = [(row["host"], row["status"]) for row in csv.DictReader(f)]
        if sorted(rows) != [("linux-nobom", "GOOD"), ("win-bom", "VULN")]:
            fails.append(f"병합 결과 불일치(같은 호스트는 최근 결과만): {sorted(rows)}")
    if fails:
        print("FAIL: merge_test\n  - " + "\n  - ".join(fails))
        return 1
    print("PASS: merge_test (BOM 있는 Windows 결과 포함 2개 호스트 병합, 같은 호스트 이전 결과 제외)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
