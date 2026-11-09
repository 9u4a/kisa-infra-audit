#!/usr/bin/env python3
"""lib/tests/fix_impact.py — 조치 운영 영향 분류표(docs/FIX_IMPACT.md) 생성기(분석자 PC/CI 전용, 1.6.0 G-02).

모든 카테고리의 조치 파일(fixes/**/*.sh·*.ps1) 머리말(앞 12줄)의 "# 원복: ..."(F4, 완전 원복 불가)·"# 영향: ..."(F5, 적용하는
순간 업무 중단 가능)과 guide.json 의 fix 등급을 모아 항목별 표를 만든다. 조치 진입점(lib/common_fix.sh fix_policy_irrev_ok,
lib/Common.psm1)은 같은 머리말을 읽어, 둘 중 하나라도 있으면 정책 파일에 "코드:irreversible" 이 있어야 적용한다 - 이 표가
정책 작성자가 그 플래그가 필요한 항목을 미리 보는 목록이다(구 D4 운영 영향표).

05_network 는 장비에 직접 적용하지 않는 명령어 생성기(fix 등급 전부 manual)라 넣지 않는다.

사용법:
  python lib/tests/fix_impact.py            # docs/FIX_IMPACT.md 다시 생성
  python lib/tests/fix_impact.py --check    # 문서가 머리말·guide.json 과 다르면 exit 1(CI static-analysis) - 다시 생성해 커밋할 것
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "FIX_IMPACT.md"
# 카테고리 → [(계열 하위 폴더, 확장자, 표에 쓸 대상 이름)] - lib/tests/guide_consistency.py FAMILIES 와 같은 단위
FAMILIES = {
    "01_unix": [("", "sh", "Unix(sh)")],
    "02_windows": [("", "ps1", "Windows")],
    "03_web": [("", "sh", "Apache/Nginx/Tomcat(sh)"), ("iis", "ps1", "IIS")],
    "05_network": [("cisco_ios", "py", "Cisco IOS(명령어 생성)")],
    "07_pc": [("", "ps1", "PC")],
    "08_dbms": [("mysql", "sh", "MySQL"), ("postgres", "sh", "PostgreSQL"), ("oracle", "sh", "Oracle"), ("mssql", "ps1", "MSSQL")],
}
TITLES = {"01_unix": "01 Unix 서버", "02_windows": "02 Windows 서버", "03_web": "03 웹 서비스", "05_network": "05 네트워크 장비", "07_pc": "07 PC", "08_dbms": "08 DBMS"}
HEAD_LINES = 12
NOTE_RE = {"rb": re.compile(r"^# 원복: (.*\S)\s*$"), "im": re.compile(r"^# 영향: (.*\S)\s*$")}


def header_notes(path: Path) -> dict[str, str]:
    """앞 12줄에서 처음 나온 원복/영향 표기(진입점 fix_rollback_note·fix_impact_note 와 같은 규칙)."""
    head = path.read_text(encoding="utf-8-sig").splitlines()[:HEAD_LINES]
    out = {}
    for key, rx in NOTE_RE.items():
        for ln in head:
            m = rx.match(ln.rstrip("\r"))
            if m:
                out[key] = m.group(1)
                break
    return out


def cell(s: str) -> str:
    return s.replace("|", "\\|") if s else "-"


def build() -> str:
    lines = [
        "# 조치 운영 영향 분류표 (FIX_IMPACT)",
        "",
        "> 이 문서는 `python lib/tests/fix_impact.py` 가 조치 파일 머리말과 guide.json 에서 생성한다 - 손으로 고치지 말 것.",
        "> CI(static-analysis)가 `--check` 로 최신인지 확인한다.",
        "",
        "- **원복 불가 사유**: 조치 파일 머리말 `# 원복:` (운영 안전 기준 F4 - 백업으로 완전히 되돌릴 수 없음)",
        "- **업무 영향**: 조치 파일 머리말 `# 영향:` (F5 - 적용하는 순간 서비스 중지·세션 끊김·계정 잠금·접근 차단·재시작 등 업무가 끊길 수 있음)",
        "- **:irreversible**: 둘 중 하나라도 있으면 정책 모드(`fix --policy`)에서 정책 파일에 `코드:irreversible` 로 적어야 적용된다"
        "(없으면 `POLICY_SKIPPED`). 대화형 실행에는 영향 없음.",
        "",
    ]
    total = need = 0
    sections: list[str] = []
    for cat, fams in FAMILIES.items():
        items = {i["code"]: i for i in json.loads((ROOT / cat / "guide.json").read_text(encoding="utf-8"))["items"]}
        rows = []
        for fam, ext, label in fams:
            d = ROOT / cat / "fixes" / fam
            if not d.is_dir():
                continue
            for f in sorted(d.glob(f"*.{ext}"), key=lambda p: (p.stem.split("-")[0], int(p.stem.split("-")[-1]))):
                it = items.get(f.stem, {})
                n = header_notes(f)
                irr = bool(n.get("rb") or n.get("im"))
                total += 1
                need += irr
                rows.append(f"| {f.stem} | {label} | {cell(it.get('title', ''))} | {it.get('fix', '-')} | {cell(n.get('rb', ''))} | "
                            f"{cell(n.get('im', ''))} | {'필요' if irr else '-'} |")
        if not rows:
            continue
        n_irr = sum(1 for r in rows if r.endswith("| 필요 |"))
        sections += [f"## {TITLES[cat]} ({len(rows)}개 조치, :irreversible 필요 {n_irr}개)", "",
                     "| 코드 | 대상 | 제목 | 등급 | 원복 불가 사유 | 업무 영향 | :irreversible |",
                     "|---|---|---|---|---|---|---|", *rows, ""]
    lines += [f"전체 조치 {total}개 중 정책에 `:irreversible` 이 필요한 조치 {need}개.", "", *sections]
    return "\n".join(lines).rstrip("\n") + "\n"


def main() -> int:
    text = build()
    if "--check" in sys.argv[1:]:
        cur = OUT.read_text(encoding="utf-8") if OUT.is_file() else ""
        if cur != text:
            print(f"FAIL: {OUT.relative_to(ROOT)} 가 최신이 아님 - python lib/tests/fix_impact.py 로 다시 생성해 커밋할 것")
            return 1
        print(f"OK: {OUT.relative_to(ROOT)} 최신")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"생성: {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
