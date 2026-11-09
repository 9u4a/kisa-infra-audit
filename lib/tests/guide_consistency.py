#!/usr/bin/env python3
"""lib/tests/guide_consistency.py — guide.json 조치 등급(fix)과 조치 스크립트의 일관성 검사(분석자 PC/CI 전용, 1.4.1).

1.4.0 검토에서 guide.json 등급과 실제 조치 스크립트가 어긋난 항목을 사람이 우연히 찾았다(KNOWN_ISSUES §3 Q-01·Q-02:
WEB-05 confirm 인데 Apache/Nginx/Tomcat 조치 없음, WEB-17 auto 인데 조치 없음). 이 검사가 CI 에서 같은 불일치를 막는다.

계열(family) = checks/ 아래 구현 단위(01·02·07: 카테고리 하나, 03_web: sh 엔진 공용 + iis, 08_dbms: 엔진별). 05_network 는
조치가 장비에 적용되지 않는 명령어 생성기라(fix 등급 전부 manual) 검사하지 않는다.

규칙:
  R1 check 가 있고 fix 가 auto/confirm 인데 그 계열의 fixes/<코드>.* 가 없으면 FAIL - lib/tests/fix_exempt.json 에 사유가
     있으면 통과. 사유는 둘만 허용:
       no-vuln-path  : check 가 VULN 을 돌려주지 않아 조치가 실행될 일이 없음 → check 코드에 VULN 을 만드는 문장이 없는지
                       기계적으로 확인한다(나중에 VULN 경로가 생기면 이 면제가 FAIL 로 바뀌어 조치 구현/등급 정정을 요구)
       engine-manual : 그 계열은 자동 조치가 안전하지 않아 수동 → guide.json 해당 항목 deviation 에 사유가 있어야 함
  R2 fix 가 manual 인데 조치 스크립트가 있으면 FAIL(진입점이 실행하지 않는 죽은 코드) - fix_exempt.json
     "_manual_with_fix" 에 사유가 있으면 통과.
  R3 면제가 더는 필요 없으면(스크립트가 생겼거나 등급이 manual 이 됨) FAIL - 오래된 면제를 남기지 않는다.
  R4 조치 스크립트에 대응하는 check 가 없으면 FAIL.
  R5 조치 스크립트 머리말(앞 12줄)에 "# 변경: <무엇을 어떤 값으로>" 가 없으면 FAIL - dry-run·적용 전 확인 목록이 이 줄을
     보여 준다(실무 적용 검증 P-24, lib/common.sh fix_change_note / lib/Common.psm1 Get-FixRollbackNote -Label 변경).
  R6 "# 원복: ..."(F4)·"# 영향: ..."(F5, 1.6.0 G-02) 은 앞 12줄 안에 내용과 함께 있어야 한다 - 진입점이 앞 12줄만 읽어 정책 모드의
     :irreversible 요구와 docs/FIX_IMPACT.md(lib/tests/fix_impact.py)를 정하므로, 밖에 있으면 조용히 무시된다.

사용법: python lib/tests/guide_consistency.py   (불일치 0 이면 exit 0)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = {
    "01_unix": [("", "sh")],
    "02_windows": [("", "ps1")],
    "03_web": [("", "sh"), ("iis", "ps1")],
    "07_pc": [("", "ps1")],
    "08_dbms": [("mssql", "ps1"), ("mysql", "sh"), ("oracle", "sh"), ("postgres", "sh")],
}
REASONS = {"no-vuln-path", "engine-manual"}
# check 가 VULN 을 만들 수 있는 문장: sh 직접 대입, 03_web web_finish 로 이어지는 violations 누적, PowerShell 결과 생성
VULN_RE = {
    "sh": re.compile(r'CHECK_STATUS="?VULN|violations="\$violations'),
    "ps1": re.compile(r'"VULN"|\'VULN\''),
}


def codes(directory: Path, ext: str) -> set[str]:
    return {p.stem for p in directory.glob(f"*.{ext}")} if directory.is_dir() else set()


def main() -> int:
    exempt = json.loads((ROOT / "lib/tests/fix_exempt.json").read_text(encoding="utf-8"))
    manual_ok = exempt.get("_manual_with_fix", {})
    errors: list[str] = []
    for cat, fams in FAMILIES.items():
        items = {i["code"]: i for i in json.loads((ROOT / cat / "guide.json").read_text(encoding="utf-8"))["items"]}
        for fam, ext in fams:
            label = f"{cat}/{fam or '-'}"
            checks = codes(ROOT / cat / "checks" / fam, ext)
            fixes = codes(ROOT / cat / "fixes" / fam, ext)
            ex = exempt.get(cat, {}).get(fam, {})
            for code in sorted(checks):
                it = items.get(code)
                if not it:
                    errors.append(f"{label} {code}: guide.json 에 없는 check")
                    continue
                grade, has_fix = it.get("fix"), code in fixes
                e = ex.get(code)
                if grade in ("auto", "confirm") and not has_fix:
                    if not e:
                        errors.append(f"{label} {code}: fix={grade} 인데 조치 스크립트 없음(R1) - 구현하거나 등급 정정, "
                                      "또는 lib/tests/fix_exempt.json 에 사유")
                    elif e.get("reason") not in REASONS:
                        errors.append(f"{label} {code}: 면제 사유 '{e.get('reason')}' 은 허용되지 않음({'/'.join(sorted(REASONS))})")
                    elif e["reason"] == "no-vuln-path":
                        src = (ROOT / cat / "checks" / fam / f"{code}.{ext}").read_text(encoding="utf-8-sig")
                        if VULN_RE[ext].search(src):
                            errors.append(f"{label} {code}: no-vuln-path 면제인데 check 가 VULN 을 만들 수 있음 - 조치 구현 또는 "
                                          "engine-manual 사유 필요")
                    elif e["reason"] == "engine-manual" and not it.get("deviation"):
                        errors.append(f"{label} {code}: engine-manual 면제인데 guide.json deviation 에 사유가 없음")
                elif e:
                    errors.append(f"{label} {code}: 면제가 더는 필요 없음(fix={grade}, 스크립트 {'있음' if has_fix else '없음'}) - "
                                  "fix_exempt.json 에서 제거(R3)")
                if grade == "manual" and has_fix and code not in manual_ok.get(cat, {}):
                    errors.append(f"{label} {code}: fix=manual 인데 조치 스크립트가 있음(R2, 진입점이 실행하지 않음)")
            for code in sorted(fixes - checks):
                errors.append(f"{label} {code}: 조치 스크립트에 대응하는 check 가 없음(R4)")
            for code in sorted(fixes):
                body = (ROOT / cat / "fixes" / fam / f"{code}.{ext}").read_text(encoding="utf-8-sig").splitlines()
                head = body[:12]
                if not any(re.match(r"# 변경: \S", ln) for ln in head):
                    errors.append(f"{label} {code}: 조치 머리말(앞 12줄)에 '# 변경: ...' 이 없음(R5)")
                for tag in ("원복", "영향"):
                    if any(ln.startswith(f"# {tag}:") for ln in body[12:]):
                        errors.append(f"{label} {code}: '# {tag}:' 가 앞 12줄 밖에 있음 - 진입점이 읽지 못함(R6)")
                    if any(re.match(rf"# {tag}:\s*$", ln) for ln in head):
                        errors.append(f"{label} {code}: '# {tag}:' 내용이 비어 있음(R6)")
            for code in sorted(set(ex) - checks):
                errors.append(f"{label} {code}: check 가 없는 항목의 면제(R3)")
        for code in sorted(manual_ok.get(cat, {})):
            it = items.get(code)
            if not it or it.get("fix") != "manual" or not any(
                    code in codes(ROOT / cat / "fixes" / fam, ext) for fam, ext in fams):
                errors.append(f"{cat} {code}: _manual_with_fix 면제가 더는 필요 없음(R3)")

    n_ex = sum(len(v) for k, c in exempt.items() if k != "_manual_with_fix" for v in c.values())
    if errors:
        print(f"FAIL: guide.json 조치 등급 ↔ 조치 스크립트 불일치 {len(errors)}건")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"OK: 조치 등급·스크립트 일치 (면제 {n_ex}건, manual 참조 구현 {sum(len(v) for v in manual_ok.values())}건)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
