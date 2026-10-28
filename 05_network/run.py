#!/usr/bin/env python3
"""05_network/run.py — 네트워크 장비 오프라인 설정파일 분석 진입점 (분석자 PC 전용, Python 3.10+).

옵션 문자는 전 카테고리와 통일한다: -l(목록) -i(항목) -g(분류) -o(출력) -h(도움말).
다른 카테고리와 달리 대상 장비에 아무것도 배치하지 않는다 — 미리 수집한 `show running-config`
텍스트 파일을 입력받아 분석자 PC에서 판정한다 (05_network/CLAUDE.md "오프라인 설정파일 분석").

사용법:
  python run.py -f running-config.txt              벤더 자동 판별 후 전체 항목 분석
  python run.py -f running-config.txt -v cisco_ios  벤더 수동 지정
  python run.py -d configs/                         디렉토리 내 다수 설정 파일 일괄 분석
  python run.py -f running-config.txt -i N-01,N-06  개별(복수) 항목만 분석
  python run.py -f running-config.txt -g 2          하위분류 단위(1=계정관리...5=기능관리) 분석
  python run.py -l                                  항목 목록만 출력 (38항목 전체)

이 스크립트는 대상 설정을 절대 변경하지 않는다 (진단 전용). 조치는 이후 로드맵의 fix.py 참고.
"""
from __future__ import annotations

import argparse
import glob
import importlib.util
import json
import os
import sys
from datetime import datetime

# Windows 콘솔 기본 코드페이지(cp949 등)에서 한글이 깨지는 것을 방지 — CRLF 관련 사례(guide.json)와
# 마찬가지로 Windows 인코딩 문제를 사전에 명시적으로 처리한다.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
LIB_DIR = os.path.join(REPO_ROOT, "lib")
sys.path.insert(0, LIB_DIR)
sys.path.insert(0, SCRIPT_DIR)

import report_common as rc  # noqa: E402
from parsers import cisco_ios  # noqa: E402

CATEGORY_NUM = "05"
CATEGORY_NAME = "네트워크 장비"
VENDORS = {"cisco_ios": cisco_ios}


def detect_vendor(text: str) -> str | None:
    for name, mod in VENDORS.items():
        if mod.detect(text):
            return name
    return None


def load_guide() -> tuple[dict, dict]:
    guide_path = os.path.join(SCRIPT_DIR, "guide.json")
    if not os.path.isfile(guide_path):
        print(f"오류: {guide_path} 가 없습니다. lib/extract_guide.py 를 먼저 실행하세요.", file=sys.stderr)
        sys.exit(2)
    with open(guide_path, encoding="utf-8") as f:
        guide = json.load(f)
    by_code = {it["code"]: it for it in guide["items"]}
    return guide, by_code


def sorted_codes(by_code: dict) -> list[str]:
    return sorted(by_code.keys(), key=lambda c: int(c.split("-")[1]))


def _load_check_module(path: str, name: str):
    # 바이트코드 캐시(__pycache__)를 거치지 않고 항상 소스를 직접 컴파일한다. 캐시는 소스 수정 시각을 초
    # 단위로 비교해, 같은 초 안에 소스가 바뀌면 낡은 판정 로직을 그대로 실행한다(실제로 N-26 이 VULN 대신
    # GOOD 을 낸 사례 - OneDrive 동기화 폴더에서 발견).
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    with open(path, encoding="utf-8") as f:
        exec(compile(f.read(), path, "exec"), mod.__dict__)  # noqa: S102 - 저장소 내 check 모듈만 로드
    return mod


def run_one_file(path: str, args, by_code: dict, tool_version: str) -> str | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print(f"오류: {path} 를 읽을 수 없습니다: {e}", file=sys.stderr)
        return None

    vendor_name = args.vendor or detect_vendor(text)
    host = os.path.splitext(os.path.basename(path))[0]

    if not vendor_name:
        print(f"[{host}] 벤더를 자동으로 판별하지 못했습니다. -v 옵션으로 지정하세요(예: -v cisco_ios).", file=sys.stderr)
        return None
    if vendor_name not in VENDORS:
        print(f"[{host}] 지원하지 않는 벤더입니다: {vendor_name}", file=sys.stderr)
        return None

    vendor_mod = VENDORS[vendor_name]
    ctx = vendor_mod.Ctx(text)
    checks_dir = os.path.join(SCRIPT_DIR, "checks", vendor_name)

    all_codes = sorted_codes(by_code)
    if args.items:
        selected = [c.strip() for c in args.items.split(",") if c.strip()]
    elif args.group:
        selected = [c for c in all_codes if str(by_code[c].get("group_no")) == args.group]
    else:
        selected = all_codes

    if not selected:
        print("오류: 대상 항목이 없습니다.", file=sys.stderr)
        return None

    out_base = args.out or os.path.join(REPO_ROOT, "output")
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    # 진단 검수 D-R10: 다른 카테고리(prepare_output_dir)와 같이 PID 를 붙여 같은 초의 두 실행이 섞이지 않게 하고,
    # 결과 폴더를 실행자 전용(700)으로 만든다 - 증적에 장비 설정 발췌가 들어간다(Windows 에서는 chmod 가 사실상 무시됨).
    out_dir = os.path.join(out_base, f"{host}_{CATEGORY_NUM}_{ts}-{os.getpid()}")
    os.makedirs(out_base, exist_ok=True)
    os.makedirs(out_dir, mode=0o700, exist_ok=False)
    os.makedirs(os.path.join(out_dir, "raw"), mode=0o700)
    for d in (out_dir, os.path.join(out_dir, "raw")):
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass

    print(f"=== 주요정보통신기반시설 자동 진단 (도구 v{tool_version} / 가이드 {rc.GUIDE_VERSION}) ===")
    print(f"카테고리   : {CATEGORY_NAME}")
    print(f"대상 파일  : {path}")
    print(f"호스트     : {host}")
    print(f"벤더       : {vendor_name}")
    print(f"대상 항목  : {len(selected)}개")
    print(f"시작 시각  : {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("-" * 72)

    items: list[dict] = []
    counts = {"VULN": 0, "MANUAL": 0, "ERROR": 0, "NA": 0, "GOOD": 0}
    for i, code in enumerate(selected, 1):
        meta = by_code.get(code, {})
        title = meta.get("title", code)
        check_file = os.path.join(checks_dir, f"{code}.py")

        if os.path.isfile(check_file):
            try:
                mod = _load_check_module(check_file, f"net_check_{vendor_name}_{code}")
                result = mod.check(ctx)
            except Exception as e:  # noqa: BLE001 - check 실행 실패는 오류 상태로 정직하게 기록
                result = {"status": "ERROR", "detail": f"check 실행 중 예외 발생: {e}", "evidence": ""}
        else:
            result = {"status": "NA", "detail": f"이 항목은 {vendor_name} 대상이 아니거나 아직 구현되지 않음", "evidence": ""}

        status = result.get("status", "ERROR")
        # 진단 검수 D-R4(S5): check 가 설정 원문(VTY 블록·snmp-server 줄)을 넘겨도 비밀번호·community·키 값이
        # 결과물(result.json·raw·report·csv)에 남지 않도록 여기서 한 번 더 마스킹한다.
        mask = getattr(vendor_mod, "mask_secrets", None) or (lambda t: t)
        detail = mask(result.get("detail", ""))
        evidence = mask(result.get("evidence", ""))

        rc.progress_show(i, len(selected), code, title, status)
        items.append({"code": code, "status": status, "detail": detail, "evidence": evidence, "severity": meta.get("severity", "")})
        counts[status] = counts.get(status, 0) + 1
        if evidence:
            with open(os.path.join(out_dir, "raw", f"{code}.txt"), "w", encoding="utf-8", newline="\n") as f:
                f.write(evidence + "\n")

    result_json = os.path.join(out_dir, "result.json")
    rc.write_result_json(result_json, items, CATEGORY_NAME, host, vendor_name, tool_version)
    rc.write_csv(os.path.join(out_dir, "result.csv"), items, by_code)
    rc.render_report_html(LIB_DIR, os.path.join(SCRIPT_DIR, "guide.json"), result_json, os.path.join(out_dir, "report.html"))
    summary = rc.write_summary(os.path.join(out_dir, "summary.txt"), CATEGORY_NAME, host, vendor_name, counts)

    print("-" * 72)
    print(summary)
    print("-" * 72)
    print(f"결과 경로: {out_dir}")
    return out_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="네트워크 장비 오프라인 설정파일 분석", add_help=True)
    parser.add_argument("-f", "--file", help="분석할 설정 파일 경로")
    parser.add_argument("-d", "--dir", dest="dirpath", help="디렉토리 내 다수 설정 파일 일괄 분석")
    parser.add_argument("-v", "--vendor", help="벤더 수동 지정 (예: cisco_ios). 생략 시 자동 판별")
    parser.add_argument("-i", "--items", help="개별(복수) 항목 코드, 콤마 구분 (예: N-01,N-06)")
    parser.add_argument("-g", "--group", help="하위분류 번호 (1=계정관리 ... 5=기능관리)")
    parser.add_argument("-l", "--list", action="store_true", help="항목 목록만 출력")
    parser.add_argument("-o", "--out", help="결과 출력 경로 (기본: ../output)")
    args = parser.parse_args()
    # 결과 파일(result.json·raw·report)이 실행자 외에는 읽히지 않게 한다(진단 검수 D-R10, 다른 카테고리의 umask 077 과 동일).
    try:
        os.umask(0o077)
    except (AttributeError, OSError):
        pass

    _, by_code = load_guide()

    if args.list:
        print(f"{'코드':<8} {'중요도':<4} {'분류':<4} 항목명")
        for code in sorted_codes(by_code):
            it = by_code[code]
            print(f"{code:<8} {it['severity']:<4} {it['group_no']:<4} {it['title']}")
        return

    if not args.file and not args.dirpath:
        parser.error("분석할 파일(-f) 또는 디렉토리(-d)를 지정하세요.")

    tool_version = rc.get_tool_version(REPO_ROOT)

    if args.file:
        files = [args.file]
    else:
        files = sorted(p for p in glob.glob(os.path.join(args.dirpath, "*")) if os.path.isfile(p))
        if not files:
            print(f"오류: {args.dirpath} 안에 파일이 없습니다.", file=sys.stderr)
            sys.exit(2)

    for path in files:
        run_one_file(path, args, by_code, tool_version)
        print()


if __name__ == "__main__":
    main()
