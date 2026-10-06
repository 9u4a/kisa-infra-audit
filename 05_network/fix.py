#!/usr/bin/env python3
"""05_network/fix.py — 네트워크 장비 조치 명령어 스크립트 생성 (분석자 PC 전용, Python 3.10+).

05_network/CLAUDE.md "조치는 실제 장비에 접속해 변경하지 않고, 벤더별 조치 명령어 스크립트만
생성한다"를 그대로 구현한다. 다른 카테고리의 fix.sh/fix.ps1 과 달리 --apply/--rollback 이 없다
— 이 스크립트는 장비에 아무것도 적용하지 않고, 사람이 검토 후 직접 입력할 명령어 텍스트
파일(remediation_<host>.txt)만 만든다.

사용법:
  python fix.py -f running-config.txt -r output/<host>_05_<ts>/result.json
  python fix.py -f running-config.txt -r <result.json> -i N-01,N-06   특정 항목만
  python fix.py -f running-config.txt -r <result.json> -v cisco_ios   벤더 수동 지정
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from datetime import datetime

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

CATEGORY_NAME = "네트워크 장비"
VENDORS = {"cisco_ios": cisco_ios}


def load_guide() -> dict:
    guide_path = os.path.join(SCRIPT_DIR, "guide.json")
    with open(guide_path, encoding="utf-8") as f:
        guide = json.load(f)
    return {it["code"]: it for it in guide["items"]}


def _load_module(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def _wrap(text: str, width: int = 90) -> list[str]:
    """guide 원문(조치방법)을 조치 명령어 스크립트 안 주석으로 넣을 때 줄바꿈 처리."""
    out = []
    for raw_line in text.splitlines() or [text]:
        line = raw_line
        while len(line) > width:
            out.append(line[:width])
            line = line[width:]
        out.append(line)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="네트워크 장비 조치 명령어 스크립트 생성", add_help=True)
    parser.add_argument("-f", "--file", required=True, help="진단에 사용한 설정 파일 경로(동일 파일)")
    parser.add_argument("-r", "--result", required=True, help="run.py 가 생성한 result.json 경로")
    parser.add_argument("-v", "--vendor", help="벤더 수동 지정 (예: cisco_ios). 생략 시 result.json의 env 필드 사용")
    parser.add_argument("-i", "--items", help="개별(복수) 항목 코드, 콤마 구분 (예: N-01,N-06)")
    parser.add_argument("-o", "--out", help="결과 출력 경로 (기본: ../output)")
    args = parser.parse_args()

    by_code = load_guide()

    with open(args.result, encoding="utf-8") as f:
        result = json.load(f)
    host = result.get("host", "unknown")
    vendor_name = args.vendor or result.get("env")
    if vendor_name not in VENDORS:
        print(f"오류: 지원하지 않거나 알 수 없는 벤더입니다: {vendor_name} (-v 로 직접 지정하세요)", file=sys.stderr)
        sys.exit(2)
    vendor_mod = VENDORS[vendor_name]

    with open(args.file, encoding="utf-8", errors="replace") as f:
        text = f.read()
    ctx = vendor_mod.Ctx(text)

    vuln_items = [it for it in result.get("items", []) if it.get("status") == "VULN"]
    if args.items:
        selected = {c.strip() for c in args.items.split(",") if c.strip()}
        vuln_items = [it for it in vuln_items if it["code"] in selected]
    vuln_items.sort(key=lambda it: int(it["code"].split("-")[1]))

    if not vuln_items:
        print("조치 대상(VULN) 항목이 없습니다.")
        return

    fixes_dir = os.path.join(SCRIPT_DIR, "fixes", vendor_name)
    out_base = args.out or os.path.join(REPO_ROOT, "output")
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = os.path.join(out_base, f"{host}_05_fix_{ts}")
    os.makedirs(out_dir, exist_ok=True)

    lines: list[str] = [
        "! =============================================================",
        f"! 주요정보통신기반시설 네트워크 장비 조치 명령어 스크립트 (도구 v{rc.get_tool_version(REPO_ROOT)} / 가이드 {rc.GUIDE_VERSION})",
        f"! 대상 호스트: {host}  /  벤더: {vendor_name}  /  생성 시각: {datetime.now():%Y-%m-%d %H:%M:%S}",
        "! 주의: 이 파일은 사람이 검토 후 직접 입력하는 참고용 스크립트이며, 이 도구가 장비에",
        "!       직접 적용하지 않는다. '!' 로 시작하는 주석 중 '[수동 조치 필요]'/'주의:' 로",
        "!       표시된 항목은 placeholder(<...>) 를 실제 값으로 바꾸기 전에는 적용하지 말 것.",
        "! =============================================================",
        "",
        "configure terminal",
    ]

    auto_count = 0
    manual_count = 0
    for it in vuln_items:
        code = it["code"]
        meta = by_code.get(code, {})
        title = meta.get("title", code)
        severity = meta.get("severity", "")
        lines.append("")
        lines.append(f"! --- {code} ({severity}) {title} ---")

        fix_file = os.path.join(fixes_dir, f"{code}.py")
        cmds: list[str] = []
        if os.path.isfile(fix_file):
            try:
                mod = _load_module(fix_file, f"net_fix_{vendor_name}_{code}")
                cmds = mod.generate(ctx) or []
            except Exception as e:  # noqa: BLE001 - 생성 실패도 정직하게 기록하고 다음 항목 계속
                cmds = []
                lines.append(f"! [오류] 명령어 생성 중 예외 발생: {e} - 가이드 조치방법을 참고해 수동으로 조치할 것")

        if cmds:
            lines.extend(cmds)
            auto_count += 1
        else:
            lines.append("! [수동 조치 필요] 아래 가이드 조치방법을 참고해 수동으로 조치할 것")
            remediation = meta.get("remediation", "") or "(가이드 조치방법 없음 - guide.json 확인 필요)"
            lines.extend(f"!   {line}" for line in _wrap(remediation))
            manual_count += 1

    lines.append("")
    lines.append("end")
    lines.append("write memory")

    out_file = os.path.join(out_dir, f"remediation_{host}.txt")
    with open(out_file, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print(f"=== 네트워크 장비 조치 명령어 스크립트 생성 (도구 v{rc.get_tool_version(REPO_ROOT)} / 가이드 {rc.GUIDE_VERSION}) ===")
    print(f"호스트     : {host}")
    print(f"벤더       : {vendor_name}")
    print(f"대상 항목  : {len(vuln_items)}개 (자동 생성 {auto_count}, 수동 조치 안내 {manual_count})")
    print(f"결과 경로  : {out_file}")
    print("이 스크립트는 장비에 직접 적용되지 않습니다 - 검토 후 placeholder 값을 교체하고 콘솔로 직접 입력하세요.")


if __name__ == "__main__":
    main()
