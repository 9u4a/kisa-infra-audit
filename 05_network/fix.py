#!/usr/bin/env python3
"""05_network/fix.py — 네트워크 장비 조치 명령어 스크립트 생성 (분석자 PC 전용, Python 3.10+).

조치는 실제 장비에 접속해 변경하지 않고, 벤더별 조치 명령어 스크립트만
생성한다. 다른 카테고리의 fix.sh/fix.ps1 과 달리 --apply/--rollback 이 없다
— 이 스크립트는 장비에 아무것도 적용하지 않고, 사람이 검토 후 직접 입력할 명령어 텍스트
파일(remediation_<host>.txt)만 만든다.

사용법:
  python fix.py -f running-config.txt -r output/<host>_05_<ts>/result.json
  python fix.py -f running-config.txt -r <result.json> -i N-01,N-06   특정 항목만
  python fix.py -f running-config.txt -r <result.json> -e cisco_ios   벤더 수동 지정(-v 도 같은 뜻, 하위 호환)
  python fix.py -f running-config.txt -r <result.json> --policy policy.txt --operator 홍길동
      정책 모드(1.6.0 G-06): 정책 파일(lib/fix_policy.py, 01~08 공통 형식)이 승인한 항목만 명령어를 만들고, 나머지는
      사유와 함께 제외 목록으로 남긴다. 호스트는 result.json 의 host. 조치 파일 머리말에 '# 원복:'·'# 영향:' 이 있는
      항목은 정책에 '코드:irreversible' 로 적혀 있어야 한다(G-02). 출력 폴더에 audit.txt·fix.log(G-03)를 남긴다.
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

import fix_policy  # noqa: E402
import report_common as rc  # noqa: E402
from parsers import cisco_ios  # noqa: E402

CATEGORY_NAME = "네트워크 장비"
CATEGORY_NUM = "05"
VENDORS = {"cisco_ios": cisco_ios}


def load_guide() -> dict:
    guide_path = os.path.join(SCRIPT_DIR, "guide.json")
    with open(guide_path, encoding="utf-8") as f:
        guide = json.load(f)
    return {it["code"]: it for it in guide["items"]}


def _load_module(path: str, name: str):
    # run.py 와 같은 이유로 바이트코드 캐시를 거치지 않고 소스를 직접 컴파일한다(낡은 캐시 실행 방지).
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    with open(path, encoding="utf-8") as f:
        exec(compile(f.read(), path, "exec"), mod.__dict__)  # noqa: S102 - 저장소 내 fix 모듈만 로드
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


def _die(msg: str, code: int = 2) -> None:
    print(f"오류: {msg}", file=sys.stderr)
    sys.exit(code)


def main() -> None:
    parser = argparse.ArgumentParser(description="네트워크 장비 조치 명령어 스크립트 생성", add_help=True)
    parser.add_argument("-f", "--file", required=True, help="진단에 사용한 설정 파일 경로(동일 파일)")
    parser.add_argument("-r", "--result", required=True, help="run.py 가 생성한 result.json 경로")
    # 환경/엔진 지정은 CLAUDE.md 옵션 문자 표대로 -e, 예전 -v/--vendor 는 하위 호환(외부 검수 C4).
    parser.add_argument("-e", "-v", "--engine", "--vendor", dest="vendor", help="벤더/엔진 수동 지정 (예: cisco_ios). 생략 시 result.json의 env 필드 사용")
    parser.add_argument("-i", "--items", help="개별(복수) 항목 코드, 콤마 구분 (예: N-01,N-06)")
    parser.add_argument("-o", "--out", help="결과 출력 경로 (기본: ../output)")
    parser.add_argument("--policy", help="조치 정책 파일(1.6.0 G-06) - 승인 항목만 명령어 생성, --operator 필수")
    parser.add_argument("--operator", help="정책 모드 실행자 이름(감사 기록 G-03)")
    args = parser.parse_args()

    # 정책 모드 옵션 검사(명세: --policy 에는 --operator 필수, --operator 단독도 exit 2) - 아무것도 만들기 전에 끝낸다.
    if args.operator is not None and args.policy is None:
        _die("--operator 는 --policy 와 함께만 쓸 수 있습니다.")
    if args.policy is not None and not (args.operator or "").strip():
        _die("--policy 에는 --operator <이름> 이 필요합니다(비어 있으면 안 됨).")
    if args.operator is not None and any(ord(ch) < 32 or ord(ch) == 127 for ch in args.operator):
        _die("--operator 에 제어 문자를 쓸 수 없습니다(감사 기록 위조 방지).")

    by_code = load_guide()

    with open(args.result, encoding="utf-8-sig") as f:
        result = json.load(f)
    host = result.get("host", "unknown")
    vendor_name = args.vendor or result.get("env")
    if vendor_name not in VENDORS:
        print(f"오류: 지원하지 않거나 알 수 없는 벤더입니다: {vendor_name} (-e 로 직접 지정하세요)", file=sys.stderr)
        sys.exit(2)
    vendor_mod = VENDORS[vendor_name]

    policy = None
    policy_section = ""
    excluded: set[str] = set()
    started_at = fix_policy.now_iso()
    if args.policy is not None:
        try:
            policy = fix_policy.parse_policy(args.policy, CATEGORY_NUM, set(by_code))
            policy_section, excluded = policy.resolve_host(host)
        except fix_policy.PolicyError as e:
            print(f"오류: 정책 파일 거부 - {args.policy}", file=sys.stderr)
            for msg in e.errors:
                print(f"  - {msg}", file=sys.stderr)
            sys.exit(2)
        except OSError as e:
            _die(f"정책 파일을 읽을 수 없습니다: {e}")

    with open(args.file, encoding="utf-8", errors="replace") as f:
        text = f.read()
    other = getattr(vendor_mod, "other_platform", lambda _t: None)(text)
    if other:  # run.py 와 같이 비 IOS 설정은 다루지 않는다(외부 검수 A14)
        print(f"오류: {args.file} 는 {other} 설정으로 보입니다 - 지원 범위(Cisco IOS) 밖입니다.", file=sys.stderr)
        sys.exit(2)
    ctx = vendor_mod.Ctx(text)

    vuln_items = [it for it in result.get("items", []) if it.get("status") == "VULN"]
    if args.items:
        selected = {c.strip() for c in args.items.split(",") if c.strip()}
        vuln_items = [it for it in vuln_items if it["code"] in selected]
    vuln_items.sort(key=lambda it: int(it["code"].split("-")[1]))

    fixes_dir = os.path.join(SCRIPT_DIR, "fixes", vendor_name)

    # 정책 모드: 대상 = VULN ∩ (-i) ∩ 정책 승인 - 호스트 제외, '# 원복:'·'# 영향:' 머리말 항목은 :irreversible 필요(G-02)
    skipped: list[tuple[str, str]] = []
    if policy is not None:
        kept = []
        for it in vuln_items:
            note = fix_policy.impact_note(os.path.join(fixes_dir, f"{it['code']}.py"))
            ok, reason = policy.decide(it["code"], policy_section, excluded, note)
            if ok:
                kept.append(it)
            else:
                skipped.append((it["code"], reason))
        vuln_items = kept

    if not vuln_items and policy is None:
        print("조치 대상(VULN) 항목이 없습니다.")
        return

    out_base = args.out or os.path.join(REPO_ROOT, "output")
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = os.path.join(out_base, f"{host}_05_fix_{ts}")
    os.makedirs(out_dir, exist_ok=True)

    audit: list[str] = []
    log_lines: list[str] = []
    if policy is not None:
        # G-03: 05 는 장비에 적용하지 않으므로 "적용" = 명령어 생성(mode=apply)
        audit = fix_policy.audit_header(policy, args.operator.strip(), host, CATEGORY_NUM, "apply", started_at)

    def log(event: str, code: str, msg: str = "") -> None:
        log_lines.append(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {event} {code}" + (f" {msg}" if msg else ""))

    lines: list[str] = [
        "! =============================================================",
        f"! 주요정보통신기반시설 네트워크 장비 조치 명령어 스크립트 (도구 v{rc.get_tool_version(REPO_ROOT)} / 가이드 {rc.GUIDE_VERSION})",
        f"! 대상 호스트: {host}  /  벤더: {vendor_name}  /  생성 시각: {datetime.now():%Y-%m-%d %H:%M:%S}",
        "! 주의: 이 파일은 사람이 검토 후 직접 입력하는 참고용 스크립트이며, 이 도구가 장비에",
        "!       직접 적용하지 않는다. '!' 로 시작하는 주석 중 '[수동 조치 필요]'/'주의:' 로",
        "!       표시된 항목은 placeholder(<...>) 를 실제 값으로 바꾸기 전에는 적용하지 말 것.",
        "! [원격 적용 안전장치 - 권장] 원격 세션으로 적용한다면 먼저 특권 모드에서 'reload in 10' 을",
        "!       입력해 10분 뒤 재부팅을 예약할 것 - 적용 중 접속이 끊겨도 10분 뒤 저장 전(이전) 설정으로",
        "!       돌아온다. 적용 후 새 세션 접속이 확인되면 'reload cancel' 로 반드시 취소할 것(잊으면 재부팅됨).",
        "! [저장] 마지막의 'write memory' 는 일부러 주석으로 두었다 - 파일 전체를 그대로 붙여넣어도 저장되지",
        "!       않으며, 새 세션으로 접속·서비스가 정상인지 확인한 뒤에만 직접 입력할 것.",
    ]
    if policy is not None:
        lines += [
            f"! [정책 모드] 정책 {policy.path} (sha256 {policy.sha256}, 유효기간 {policy.expires}, 적용 구역 {policy_section})",
            f"!       승인자 {policy.approver} / 실행자 {args.operator.strip()} - 정책이 승인한 항목만 아래에 들어 있다.",
        ]
        if skipped:
            lines.append(f"! [정책 제외 {len(skipped)}건] 아래 VULN 항목은 명령어를 만들지 않았다:")
            lines += [f"!   {code}: {reason}" for code, reason in skipped]
    lines += [
        "! =============================================================",
        "",
        "configure terminal",
    ]

    auto_count = 0
    manual_count = 0
    failed: list[str] = []
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
                failed.append(code)
                lines.append(f"! [오류] 명령어 생성 중 예외 발생: {e} - 가이드 조치방법을 참고해 수동으로 조치할 것")

        if cmds:
            lines.extend(cmds)
            auto_count += 1
            log("APPLIED", code, "명령어 생성")
        else:
            lines.append("! [수동 조치 필요] 아래 가이드 조치방법을 참고해 수동으로 조치할 것")
            remediation = meta.get("remediation", "") or "(가이드 조치방법 없음 - guide.json 확인 필요)"
            lines.extend(f"!   {line}" for line in _wrap(remediation))
            manual_count += 1
            if code in failed:
                log("FAILED", code, "명령어 생성 예외 - 수동 조치 안내로 대체")
            else:
                log("MANUAL", code, "자동 명령 없음 - 수동 조치 안내")

    lines.append("")
    lines.append("end")
    lines.append("! 새 세션으로 접속·서비스가 정상인지 확인한 뒤에만 아래를 직접 입력해 저장할 것(저장 전 재부팅 시 이전 설정으로 돌아감)")
    lines.append("! reload cancel   (reload in 을 예약했다면)")
    lines.append("! write memory")

    out_file = os.path.join(out_dir, f"remediation_{host}.txt")
    if vuln_items:
        with open(out_file, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")

    if policy is not None:
        for code, reason in skipped:
            log("POLICY_SKIPPED", code, reason)
        # 종료 건수 키는 sh/PowerShell 과 같다. 05 는 장비 적용·y/N·dry-run 이 없어 declined·skipped·preview 는 항상 0.
        footer = [
            f"finished_at={fix_policy.now_iso()}",
            f"applied={auto_count}",
            f"failed={len(failed)}",
            "declined=0",
            "skipped=0",
            f"manual={manual_count - len(failed)}",
            "preview=0",
            f"policy_skipped={len(skipped)}",
            f"failed_codes={','.join(failed)}",
        ]
        with open(os.path.join(out_dir, "audit.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(audit + footer) + "\n")
        with open(os.path.join(out_dir, "fix.log"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(audit + log_lines + footer) + "\n")

    print(f"=== 네트워크 장비 조치 명령어 스크립트 생성 (도구 v{rc.get_tool_version(REPO_ROOT)} / 가이드 {rc.GUIDE_VERSION}) ===")
    print(f"호스트     : {host}")
    print(f"벤더       : {vendor_name}")
    if policy is not None:
        print(f"정책       : {policy.path} (승인자 {policy.approver}, 유효기간 {policy.expires}, 적용 구역 {policy_section})")
    print(f"대상 항목  : {len(vuln_items)}개 (자동 생성 {auto_count}, 수동 조치 안내 {manual_count})")
    if policy is not None:
        print(f"정책 제외  : {len(skipped)}개")
        for code, reason in skipped:
            print(f"  - {code}: {reason}")
        print(f"감사 기록  : {os.path.join(out_dir, 'audit.txt')}")
    if failed:
        print(f"실패 항목  : {', '.join(failed)} (명령어 생성 예외 - 수동 조치 안내로 대체)")
    if vuln_items:
        print(f"결과 경로  : {out_file}")
        print("이 스크립트는 장비에 직접 적용되지 않습니다 - 검토 후 placeholder 값을 교체하고 콘솔로 직접 입력하세요.")
    else:
        print("정책이 승인한 조치 대상이 없어 명령어 스크립트를 만들지 않았습니다.")


if __name__ == "__main__":
    main()
