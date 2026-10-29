#!/usr/bin/env python3
"""lib/tests/coverage.py — 판정 양방향 검증 커버리지(분석자 PC/CI 전용, 1.4.0).

각 (카테고리, 엔진, 항목)이 테스트 픽스처에서 "양호 상태 → GOOD" 과 "취약 상태 → VULN" 을 모두 검증받는지 센다.
v1.3.3 까지는 항목 대부분이 한 상태로만 고정돼 있어(Windows 2/64, PC 2/18, DBMS 1/26 만 양방향) check 가 항상 같은
값을 돌려주도록 망가져도 테스트가 잡지 못했다(KNOWN_ISSUES 1-8 X-08).

기대값의 출처(각 카테고리 테스트 러너가 실제로 실행·비교하는 것만 센다):
  1) tests/fixtures/expected_<mode>.json / expected_<engine>_<mode>.json  - 전역 vuln/hardened 픽스처
     (05_network 의 expected_edge.json 처럼 mode 가 다른 이름이어도 같은 형식이면 포함)
  2) tests/fixtures/cases/cases.json  - 항목별 케이스. 한 이미지에서 동시에 만들 수 없는 상태(서비스 미설치/설치+취약,
     서로 배타적인 설정)를 항목 단위로 세팅한다. 형식:
       [{"code": "U-05", "engine": "debian", "name": "path-dot", "expect": "VULN"}, ...]
     러너는 이 파일을 읽어 모든 케이스를 실행해야 한다(케이스를 건너뛰면 러너가 FAIL - 여기서는 선언만 센다).

면제(lib/tests/coverage_exempt.json): 양방향 검증을 요구하지 않는 (카테고리, 엔진, 항목)과 사유.
  {"<카테고리>": {"<코드>": {"reason": "...", "engines": ["..."] (생략 시 전 엔진), "note": "..."}}}
  reason 은 아래 셋만 허용한다.
    manual-by-design : 가이드상 정책·인적 판단 항목이라 check 가 항상 MANUAL (기대값에 MANUAL 이 1건 이상 있어야 함)
    na-for-engine    : 그 엔진은 가이드 대상이 아님 (기대값이 있다면 NA 또는 MANUAL 이어야 함 - 대상 외 엔진에서
                       근거만 제공하는 check 가 있음)
    env-unavailable  : CI 에서 만들 수 없는 환경(KNOWN_ISSUES L-xx). note 에 L-ID 필수, 한 방향이라도 검증된 것은 표시
  08_dbms 는 checks/<engine>/<코드>.* 가 없으면 자동으로 na-for-engine, 03_web 은 guide.json envs 에 엔진이 없으면 자동 면제.

사용법:
  python lib/tests/coverage.py              # 매트릭스 요약 출력(정보용, 항상 exit 0)
  python lib/tests/coverage.py --strict     # 면제 아닌 항목이 한 방향이라도 비면 exit 1 (CI 게이트)
  python lib/tests/coverage.py --list-missing [카테고리]   # 빠진 항목 목록
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# 카테고리별 검증 엔진(이미 지원하는 실사용 대상 - 새 환경 추가 아님). 첫 번째가 엔진 표기 없는 expected_<mode>.json 의 엔진.
ENGINES = {
    "01_unix": ["debian"],
    "02_windows": ["server"],
    "03_web": ["apache", "apache-debian", "nginx", "tomcat", "iis"],
    "05_network": ["cisco_ios"],
    "07_pc": ["windows"],
    "08_dbms": ["mysql", "postgres", "oracle", "mssql"],
}
REASONS = {"manual-by-design", "na-for-engine", "env-unavailable"}


def load_json(path: str):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def guide_items(cat: str) -> list[dict]:
    return load_json(os.path.join(ROOT, cat, "guide.json"))["items"]


def collect(cat: str) -> dict[tuple[str, str], set[str]]:
    """(엔진, 코드) -> 기대 상태 집합"""
    engines = ENGINES[cat]
    seen: dict[tuple[str, str], set[str]] = {}
    fx = os.path.join(ROOT, cat, "tests", "fixtures")
    for p in sorted(glob.glob(os.path.join(fx, "expected*.json"))):
        stem = os.path.basename(p)[len("expected_"):-len(".json")]
        engine = engines[0]
        for e in sorted(engines, key=len, reverse=True):  # apache-debian 이 apache 보다 먼저
            if stem.startswith(e + "_"):
                engine = e
                break
        data = load_json(p)
        if isinstance(data, dict) and "items" in data:
            data = data["items"]
        for code, st in data.items():
            seen.setdefault((engine, code), set()).add(st)
    cases = os.path.join(fx, "cases", "cases.json")
    if os.path.isfile(cases):
        for c in load_json(cases):
            eng = c.get("engine") or engines[0]
            seen.setdefault((eng, c["code"]), set()).add(c["expect"])
    return seen


def auto_exempt(cat: str, engine: str, item: dict) -> str | None:
    code = item["code"]
    if cat == "08_dbms":
        if not glob.glob(os.path.join(ROOT, cat, "checks", engine, code + ".*")):
            return "na-for-engine"
    if cat == "03_web":
        env = "apache" if engine == "apache-debian" else engine
        envs = item.get("envs") or []
        if envs and env not in envs:
            return "na-for-engine"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--list-missing", nargs="?", const="*", default=None)
    args = ap.parse_args()

    exempt_path = os.path.join(ROOT, "lib", "tests", "coverage_exempt.json")
    exempt = load_json(exempt_path) if os.path.isfile(exempt_path) else {}
    problems: list[str] = []
    missing_rows: list[str] = []
    print(f"{'카테고리':<11} {'엔진':<14} {'대상':>4} {'양방향':>6} {'면제':>5} {'누락':>5}")
    tot = {"target": 0, "both": 0, "exempt": 0, "missing": 0}
    for cat, engines in ENGINES.items():
        items = guide_items(cat)
        seen = collect(cat)
        ex_cat = exempt.get(cat, {})
        for code, e in ex_cat.items():
            if e.get("reason") not in REASONS:
                problems.append(f"{cat} {code}: 면제 사유 '{e.get('reason')}' 는 허용되지 않음({sorted(REASONS)})")
            if e.get("reason") == "env-unavailable" and not re.search(r"L-\d+", e.get("note", "")):
                problems.append(f"{cat} {code}: env-unavailable 면제는 note 에 KNOWN_ISSUES L-ID 필요")
        for engine in engines:
            n_target = n_both = n_ex = n_miss = 0
            for it in items:
                code = it["code"]
                states = seen.get((engine, code), set())
                reason = auto_exempt(cat, engine, it)
                e = ex_cat.get(code)
                if not reason and e and (not e.get("engines") or engine in e["engines"]):
                    reason = e.get("reason")
                n_target += 1
                if {"GOOD", "VULN"} <= states:
                    n_both += 1
                    continue
                if reason:
                    n_ex += 1
                    if reason == "manual-by-design" and "MANUAL" not in states:
                        problems.append(f"{cat}/{engine} {code}: manual-by-design 인데 MANUAL 기대값이 없음")
                    if reason == "na-for-engine" and states - {"NA", "MANUAL"}:
                        problems.append(f"{cat}/{engine} {code}: na-for-engine 인데 기대값이 {sorted(states)}")
                    continue
                n_miss += 1
                have = ",".join(sorted(states)) or "-"
                need = "/".join(s for s in ("GOOD", "VULN") if s not in states)
                missing_rows.append(f"{cat}/{engine} {code}: 있음={have} 필요={need}")
            print(f"{cat:<11} {engine:<14} {n_target:>4} {n_both:>6} {n_ex:>5} {n_miss:>5}")
            for k, v in (("target", n_target), ("both", n_both), ("exempt", n_ex), ("missing", n_miss)):
                tot[k] += v
    print(f"{'합계':<11} {'':<14} {tot['target']:>4} {tot['both']:>6} {tot['exempt']:>5} {tot['missing']:>5}")
    n_manual_ex = sum(1 for c in exempt.values() for e in c.values() if e.get("reason") != "na-for-engine")
    print(f"수동 면제 항목 수(na-for-engine 제외): {n_manual_ex} - 늘어나면 리뷰 대상")

    if args.list_missing is not None:
        for r in missing_rows:
            if args.list_missing == "*" or r.startswith(args.list_missing):
                print("  누락 " + r)
    for p in problems:
        print("  문제 " + p)
    if args.strict and (missing_rows or problems):
        print(f"FAIL: 양방향 검증 누락 {len(missing_rows)}건, 면제 규칙 위반 {len(problems)}건")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
