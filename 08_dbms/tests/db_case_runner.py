#!/usr/bin/env python3
"""08_dbms/tests/db_case_runner.py — MySQL/PostgreSQL/Oracle 항목별 판정 양방향 케이스 러너(분석자 PC/CI 전용, 1.4.0).

run_tests.sh 가 DB 서버 컨테이너(로컬 모드: 진단을 서버 안에서 실행)를 띄운 뒤 호출한다.
  python3 08_dbms/tests/db_case_runner.py <engine> <container>

fixtures/cases/cases.json 에서 engine 이 일치하는 선언을 모두 실행한다(하나라도 실행하지 못하면 FAIL). 케이스마다:
  ① setup → verify(만든 상태를 DB/파일에서 다시 읽어 확인 - 안 먹었으면 FAIL)
  ② run.sh -i <code> 판정 = cases.json expect (guide.json 판단기준에서 정한 기대값)
  ③ meta FIX=1 이고 expect=VULN 이면 조치 검증: 조치 전 상태 스냅샷 → fix.sh --apply(가상 터미널 답 입력) →
     changes.log 가 APPLIED 이고 재진단 = FIXEXPECT(GOOD 또는 정책 판단 항목의 MANUAL) → fix.sh --rollback →
     RB=same 이면 스냅샷이 조치 전과 같아야 함, RB=irreversible 이면 "원복 불가" 기록이 있어야 함
  ④ restore → 스냅샷이 러너 시작 시점(기준선)과 같아야 함(다음 케이스로 상태가 새지 않게)
실제 구현은 컨테이너 안의 fixtures/cases/db_cases.sh(POSIX sh)에 있다.
"""
from __future__ import annotations

import difflib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CASES_SH = "/infra/08_dbms/tests/fixtures/cases/db_cases.sh"
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def sh(container: str, *args: str, timeout: int = 900) -> tuple[int, str]:
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    p = subprocess.run(["docker", "exec", "-u", "0", container, "sh", CASES_SH, *args], capture_output=True,
                       timeout=timeout, env=env)
    return p.returncode, p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")


def kv(text: str) -> dict[str, str]:
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out.setdefault(k.strip(), v.strip())
    return out


def diff(a: str, b: str) -> str:
    d = list(difflib.unified_diff(a.splitlines(), b.splitlines(), "기준", "이후", lineterm="", n=0))
    return "\n      ".join(d[2:22])


def main() -> int:
    engine, container = sys.argv[1], sys.argv[2]
    with open(os.path.join(ROOT, "08_dbms", "tests", "fixtures", "cases", "cases.json"), encoding="utf-8-sig") as f:
        cases = [c for c in json.load(f) if c.get("engine") == engine]
    only = os.environ.get("KISA_CASES_ONLY")  # 개발용: 콤마 구분 케이스 이름만(전체 실행 검사는 건너뜀)
    if only:
        cases = [c for c in cases if c["name"] in only.split(",")]
    if not cases:
        print(f"FAIL: {engine}/cases - cases.json 에 {engine} 케이스가 없음")
        return 1
    rc, base = sh(container, engine, "snapshot")
    if rc != 0 or not base.strip():
        print(f"FAIL: {engine}/cases - 기준 상태 스냅샷 실패\n{base[-800:]}")
        return 1
    fails: list[str] = []
    executed = 0
    n_fix = 0
    t_all = time.time()
    for c in cases:
        name, code, expect = c["name"], c["code"], c["expect"]
        label = f"{engine}/{code}/{name}"
        t0 = time.time()
        rc, meta_out = sh(container, engine, name, "meta")
        meta = kv(meta_out)
        if rc != 0 or not meta.get("MODE"):
            fails.append(f"{label}: db_cases.sh 에 케이스 정의가 없음({meta_out.strip()[:200]})")
            continue
        problems: list[str] = []
        try:
            rc, out = sh(container, engine, name, "setup")
            if rc != 0:
                problems.append(f"setup 실패(rc={rc}): {out.strip()[-300:]}")
            rc, out = sh(container, engine, name, "verify")
            if rc != 0:
                problems.append(f"setup 후 상태 확인 실패(설정이 적용되지 않음): {out.strip()[-300:]}")
            rc, out = sh(container, engine, name, "run", code)
            got = kv(out).get("STATUS", "")
            if got != expect:
                problems.append(f"판정 기대={expect} 실제={got or '(없음)'}")
            executed += 1
            if meta.get("FIX") == "1" and expect == "VULN" and not problems:
                n_fix += 1
                _, pre = sh(container, engine, "snapshot")
                rc, out = sh(container, engine, name, "fix", code)
                r = kv(out)
                want = meta.get("FIXEXPECT", "GOOD")
                if r.get("FIX") != "APPLIED" or r.get("AFTER") != want or r.get("RECHECK") != want:
                    fo = subprocess.run(["docker", "exec", container, "tail", "-n", "15", "/tmp/kisa_case/fix.out"],
                                        capture_output=True).stdout.decode("utf-8", "replace")
                    problems.append(f"조치 기대 APPLIED/재진단 {want}, 실제 FIX={r.get('FIX')} RECHECK={r.get('RECHECK')} "
                                    f"AFTER={r.get('AFTER')}\n      | " + "\n      | ".join(fo.splitlines()))
                rc, out = sh(container, engine, name, "rollback")
                rb = kv(out)
                if meta.get("RB") == "irreversible":
                    if rb.get("RB_IRREV") != "1":
                        problems.append(f"원복 불가 항목인데 원복 결과에 '원복 불가' 기록이 없음({out.strip()[:200]})")
                else:
                    _, post = sh(container, engine, "snapshot")
                    if rb.get("RB_RC") != "0":
                        problems.append(f"원복 실패 RB_RC={rb.get('RB_RC')}")
                    if post != pre:
                        problems.append("원복 후 상태가 조치 전(취약 상태)과 다름:\n      " + diff(pre, post))
        finally:
            rc, out = sh(container, engine, name, "restore")
            if rc != 0:
                problems.append(f"restore 실패(rc={rc}): {out.strip()[-300:]}")
            _, now = sh(container, engine, "snapshot")
            if now != base:
                problems.append("restore 후 상태가 기준선과 다름(다음 케이스 오염):\n      " + diff(base, now))
        dt = time.time() - t0
        if problems:
            fails.append(f"{label}: " + " / ".join(problems))
            print(f"  FAIL {label} ({dt:.0f}s)")
        else:
            print(f"  ok   {label} = {expect}{' +조치·원복' if meta.get('FIX') == '1' and expect == 'VULN' else ''} ({dt:.0f}s)")
    if only:
        fails.append(f"KISA_CASES_ONLY 로 일부만 실행함({len(cases)}개) - 전체 실행 아님")
    if executed != len(cases):
        fails.append(f"cases.json 의 {engine} 케이스 {len(cases)}개 중 {executed}개만 실행됨")
    print(("FAIL" if fails else "PASS") + f": dbms/{engine}/cases ({executed}/{len(cases)}개 실행, 조치 검증 {n_fix}개, {time.time() - t_all:.0f}s)")
    for f_ in fails:
        print("  - " + f_)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
