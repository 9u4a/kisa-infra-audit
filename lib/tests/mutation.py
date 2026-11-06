#!/usr/bin/env python3
"""lib/tests/mutation.py — 변이(mutation) 검증: 테스트가 "망가진 check" 를 실제로 잡는지 확인한다(분석자 PC/CI 전용, 1.5.0 D1).

coverage.py 는 각 (카테고리, 엔진, 항목)에 GOOD·VULN 기대값이 "선언"돼 있는지만 센다. 이 스크립트는 check 를 일부러 망가뜨려
(항상 GOOD / 항상 VULN 을 돌려주는 스텁으로 바꿔) 카테고리 테스트를 돌리고, 그 항목의 기대값 비교가 실제로 FAIL 하는지 본다.
FAIL 하지 않는 항목(= 살아남은 변이)은 테스트가 그 check 의 결과를 보지 않는다는 뜻이다(1.4.0 에 손으로 한 번 했던 음성 대조
"check 강제 GOOD" 을 전 항목 자동으로).

동작
  1) 저장소를 임시 폴더로 복사한다(git ls-files: 추적 + 추적 안 된 비무시 파일). 원본 작업 트리는 건드리지 않는다.
  2) 사본의 <카테고리>/checks/ 아래 항목 check 파일(<코드>.sh/.py/.ps1)을 전부 스텁으로 바꾼다.
     - sh  : CHECK_STATUS=<M> (run_check_isolated 가 source)
     - py  : def check(ctx): return {"status": "<M>", ...} (05_network)
     - ps1 : return New-CheckResult -Code <코드> -Status <M> (Windows 계열, UTF-8 BOM 유지)
  3) 사본에서 그 카테고리의 테스트 러너를 그대로 실행한다(Docker 이미지는 사본으로 빌드된다 - 이미지 이름은 같아서 다음 정상
     실행이 다시 빌드한다. 정상 테스트와 동시에 돌리지 말 것).
  4) 출력의 실패 줄(FAIL…, "  - …", "  FAIL …")에서 항목 코드와 엔진을 뽑아 "잡힌 (엔진, 코드)" 집합을 만든다.
  5) coverage.collect() 의 기대값 중 변이 값 M 과 다른 기대값이 있는 (엔진, 코드)는 반드시 잡혀야 한다. 안 잡힌 것이 생존 변이.

사용법(저장소 루트)
  python3 lib/tests/mutation.py 05_network                       # 두 변이(GOOD, VULN) 모두
  python3 lib/tests/mutation.py 03_web --engines nginx --mutant GOOD
  python3 lib/tests/mutation.py 08_dbms --engines mysql postgres
  python3 lib/tests/mutation.py 01_unix --keep                   # 사본·로그를 남긴다(분석용)
종료 코드: 0 = 생존 변이 없음, 1 = 생존 변이 있음, 2 = 실행 오류.
한계: 실패 줄의 코드로 판정하므로, 다른 이유(조치 검증 등)로 같은 항목이 FAIL 해도 "잡힘"으로 센다 - 테스트 묶음 전체가 그
check 의 변화를 알아챘다는 뜻이라 의도한 정의다. 엔진 이름이 없는 실패 줄은 바로 앞 머리줄(FAIL:/PASS:/[*])의 엔진을 쓴다.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coverage  # noqa: E402  (같은 폴더의 coverage.py - 기대값 수집을 그대로 재사용)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PREFIX = {"01_unix": "U", "02_windows": "W", "03_web": "WEB", "05_network": "N", "07_pc": "PC", "08_dbms": "D"}
# 러너가 함께 돌리지만 coverage 가 세지 않는 재현 층(같은 엔진의 다른 배포 레이아웃) - 이 엔진 이름이 붙은 줄은 집계하지 않는다
EXTRA_ENGINES = {"01_unix": ["rhel"], "03_web": ["apache-rhel", "tomcat-rhel"]}
CODE_FILE = re.compile(r"^(?:U|W|WEB|N|PC|D)-\d{2}\.(sh|py|ps1)$")


def ps(script: str, *args: str) -> list[str]:
    """Windows PowerShell 5.1 로 저장소 .ps1 실행. 출력은 UTF-8 로(기본 OEM 코드페이지면 한글이 깨진다 - 코드는 ASCII 라 판정엔 무관)."""
    inner = "[Console]::OutputEncoding = [Text.Encoding]::UTF8; & '" + script + "' " + " ".join(args) + "; exit $LASTEXITCODE"
    return ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", inner]


WIN_ENGINES = {"iis", "mssql"}


def runners(cat: str, engines: list[str]) -> tuple[list[list[str]], dict]:
    """(차례로 실행할 명령들, 추가 환경 변수). 명령 하나라도 실패하면 러너 실패로 본다."""
    env = {}
    if cat == "01_unix":
        return [["sh", "01_unix/tests/run_tests.sh"]], env
    if cat == "03_web":
        if engines == ["iis"]:
            return [ps(".\\03_web\\tests\\run_tests_iis.ps1")], env
        if "iis" in engines:
            raise SystemExit("오류: 03_web iis 는 따로 돌린다(--engines iis, Windows 러너)")
        env["WEB_ENGINES"] = " ".join(engines)
        return [["sh", "03_web/tests/run_tests.sh"]], env
    if cat == "05_network":
        return [[sys.executable, "05_network/tests/run_tests.py"]], env
    if cat == "08_dbms":
        if engines == ["mssql"]:
            return [ps(".\\08_dbms\\tests\\run_tests_mssql.ps1")], env
        if "mssql" in engines:
            raise SystemExit("오류: 08_dbms mssql 은 따로 돌린다(--engines mssql, Windows 러너)")
        return [["sh", "08_dbms/tests/run_tests.sh", *engines]], env
    if cat in ("02_windows", "07_pc"):
        # 항목별 케이스(case_runner.ps1) + 전역 vuln/hardened 픽스처(run_tests.ps1) - 둘 다 레지스트리를 실제로 바꾼다(CI 러너 전용).
        # run_tests.ps1 은 픽스처 상태를 되돌리지 않으므로 기준선 스냅샷을 찍는 케이스 러너를 먼저 돌린다.
        return [ps(".\\02_windows\\tests\\case_runner.ps1", "-Category", cat), ps(f".\\{cat}\\tests\\run_tests.ps1")], env
    raise SystemExit(f"오류: 알 수 없는 카테고리 {cat}")


def default_engines(cat: str) -> list[str]:
    if cat == "03_web":
        return [e for e in coverage.ENGINES[cat] if e != "iis"]  # iis 는 --engines iis(Windows)
    if cat == "08_dbms":
        return ["mysql", "postgres"]  # oracle 은 --engines oracle 로 따로(이미지가 무거움), mssql 은 --engines mssql(Windows)
    return list(coverage.ENGINES[cat])


def copy_repo(dst: str) -> None:
    files = subprocess.run(["git", "ls-files", "-z", "-co", "--exclude-standard"], cwd=ROOT, capture_output=True,
                           check=True).stdout.decode("utf-8").split("\0")
    for rel in files:
        if not rel:
            continue
        src = os.path.join(ROOT, rel)
        if not os.path.isfile(src):
            continue
        out = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copy2(src, out)


def mutate(dst: str, cat: str, status: str) -> int:
    n = 0
    for base, _, names in os.walk(os.path.join(dst, cat, "checks")):
        for name in names:
            m = CODE_FILE.match(name)
            if not m:
                continue
            code, ext = name.rsplit(".", 1)[0], m.group(1)
            p = os.path.join(base, name)
            if ext == "sh":
                body = f'# mutation stub\nCHECK_STATUS="{status}"; CHECK_DETAIL="mutation stub"; CHECK_EVIDENCE=""\n'
                open(p, "w", encoding="utf-8", newline="\n").write(body)
            elif ext == "py":
                body = f'def check(ctx):\n    return {{"status": "{status}", "detail": "mutation stub", "evidence": ""}}\n'
                open(p, "w", encoding="utf-8", newline="\n").write(body)
            else:
                body = f'return New-CheckResult -Code "{code}" -Status "{status}" -Detail "mutation stub" -Evidence ""\r\n'
                open(p, "w", encoding="utf-8-sig", newline="").write(body)
            n += 1
    return n


def engine_token(line: str, names: list[str]) -> str | None:
    for e in sorted(names, key=len, reverse=True):
        if re.search(rf"(?<![\w-]){re.escape(e)}(?![\w-])", line):
            return e
    return None


def killed_from(output: str, cat: str, engines: list[str]) -> set[tuple[str, str]]:
    names = list(coverage.ENGINES[cat]) + EXTRA_ENGINES.get(cat, [])
    code_re = re.compile(rf"(?<![\w-]){PREFIX[cat]}-\d{{2}}(?!\d)")
    # 엔진 하나만 돌릴 때(단일 엔진 카테고리, --engines nginx, iis/mssql 전용 러너)는 엔진 이름이 없는 줄도 그 엔진이다
    default = engines[0] if len(engines) == 1 else None
    ctx = default
    killed: set[tuple[str, str]] = set()
    for raw in output.splitlines():
        line = raw.rstrip()
        head = line.lstrip()
        if head.startswith(("FAIL:", "PASS:", "[*]")):
            ctx = engine_token(line, names) or default
        failing = head.startswith(("FAIL", "- ")) or line.startswith("  - ")
        if not failing:
            continue
        eng = engine_token(line, names) or ctx
        if eng is None or eng not in engines:
            continue
        for code in code_re.findall(line):
            killed.add((eng, code))
    return killed


def has_check(cat: str, engine: str, code: str) -> bool:
    """변이시킬 check 파일이 있는지. 08_dbms 는 checks/<엔진>/<코드>.* 가 없으면 진입점이 NA 를 직접 낸다(바꿀 check 가 없음)."""
    if cat == "08_dbms":
        sub = [engine]
    elif cat == "03_web":
        sub = ["iis"] if engine == "iis" else [""]
    elif cat == "05_network":
        sub = [engine]
    else:
        sub = [""]
    return any(os.path.isfile(os.path.join(ROOT, cat, "checks", s, f"{code}.{ext}"))
               for s in sub for ext in ("sh", "py", "ps1"))


def targets(cat: str, engines: list[str], status: str) -> dict[tuple[str, str], set[str]]:
    seen = coverage.collect(cat)
    return {k: v for k, v in seen.items() if k[0] in engines and (v - {status}) and has_check(cat, k[0], k[1])}


def report(cat: str, engines: list[str], status: str, out: str, rc: int, note: str) -> int:
    killed = killed_from(out, cat, engines)
    want = targets(cat, engines, status)
    survivors = sorted(k for k in want if k not in killed)
    print(f"[mutation] {cat} 변이={status}: 러너 rc={rc}, {note}, 대상 {len(want)} 중 잡힘 {len(want) - len(survivors)}, "
          f"생존 {len(survivors)}")
    if rc == 0:
        print(f"FAIL: {cat} 변이={status} - 모든 check 를 바꿨는데 러너가 성공(rc=0)함 - 테스트가 판정을 보지 않음")
    for eng, code in survivors:
        print(f"  생존: {cat}/{eng}/{code} (기대값 {sorted(want[(eng, code)])} - 항상 {status} 인 check 를 잡지 못함)")
    return len(survivors) + (1 if rc == 0 else 0)


def log_path(log_dir: str, cat: str, engines: list[str], status: str) -> str:
    return os.path.join(log_dir, f"mutation_{cat}_{'-'.join(engines)}_{status}.log")


def run_one(cat: str, engines: list[str], status: str, keep: bool, log_dir: str, reparse: bool) -> int:
    log = log_path(log_dir, cat, engines, status)
    if reparse:
        text = open(log, encoding="utf-8").read()
        rc = 0 if text.startswith("# rc=0\n") else 1
        return report(cat, engines, status, text, rc, f"저장된 로그 {log}")
    tmp = tempfile.mkdtemp(prefix=f"kisa_mut_{cat}_{status}_")
    try:
        copy_repo(tmp)
        n = mutate(tmp, cat, status)
        cmds, extra = runners(cat, engines)
        env = dict(os.environ, **extra)
        t0 = time.time()
        out, rc = "", 0
        for cmd in cmds:
            print(f"[mutation] {cat} 변이={status} check {n}개 → {' '.join(cmd)} (엔진 {' '.join(engines)})", flush=True)
            p = subprocess.run(cmd, cwd=tmp, env=env, capture_output=True)
            out += p.stdout.decode("utf-8", errors="replace") + p.stderr.decode("utf-8", errors="replace")
            rc = rc or p.returncode  # 모든 러너가 성공(rc=0)했을 때만 0 - 그게 곧 "아무것도 못 잡음"
        open(log, "w", encoding="utf-8").write(f"# rc={rc}\n" + out)
        return report(cat, engines, status, out, rc, f"{time.time() - t0:.0f}초, 로그 {log}")
    finally:
        if keep:
            print(f"[mutation] 사본 유지: {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser(description="check 변이 검증(항상 GOOD / 항상 VULN 스텁으로 바꿔 테스트가 잡는지)")
    ap.add_argument("category", choices=sorted(PREFIX))
    ap.add_argument("--engines", nargs="+", help="대상 엔진(기본: 03 은 IIS 제외 전부, 08 은 mysql postgres)")
    ap.add_argument("--mutant", choices=["GOOD", "VULN", "both"], default="both")
    ap.add_argument("--keep", action="store_true", help="임시 사본을 지우지 않음")
    ap.add_argument("--log-dir", default=tempfile.gettempdir())
    ap.add_argument("--reparse", action="store_true", help="실행하지 않고 저장된 로그(--log-dir)로 다시 집계")
    a = ap.parse_args()
    engines = a.engines or default_engines(a.category)
    bad_eng = [e for e in engines if e not in coverage.ENGINES[a.category]]
    if bad_eng:
        print(f"오류: {a.category} 에 없는 엔진 {bad_eng}")
        return 2
    total_bad = 0
    for st in (["GOOD", "VULN"] if a.mutant == "both" else [a.mutant]):
        total_bad += run_one(a.category, engines, st, a.keep, a.log_dir, a.reparse)
    print(("FAIL" if total_bad else "PASS") + f": mutation/{a.category} ({' '.join(engines)}) - 생존 변이 {total_bad}건")
    return 1 if total_bad else 0


if __name__ == "__main__":
    sys.exit(main())
