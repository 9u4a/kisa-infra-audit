#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
가이드 PDF -> 카테고리별 guide.json / guide.md 추출기

근거 문서: 주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드 (2026판)

사용법:
    python lib/extract_guide.py                # 전체 카테고리 추출
    python lib/extract_guide.py --only 01_unix  # 특정 카테고리만

주의:
- 이 스크립트의 출력(guide.json/guide.md)이 이후 모든 check/fix 구현의 유일한 기준이 된다.
- PDF 원문을 다시 참조하지 말고, 생성된 guide.md/json 을 참조할 것.
"""
import argparse
import json
import re
import sys
from pathlib import Path

try:
    import pymupdf  # PyMuPDF
except ImportError:  # pragma: no cover
    print("PyMuPDF(pymupdf) 가 필요합니다: pip install pymupdf", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parent.parent
PDF_PATH = ROOT / "주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드.pdf"
GUIDE_VERSION = "2026"

# 카테고리 정의: (폴더, 코드 접두어, 가이드상 카테고리명, 시작 페이지, 끝 페이지(포함), 기대 항목 수)
CATEGORIES = [
    {"dir": "01_unix", "prefix": "U", "name": "UNIX", "start": 7, "end": 171, "expected": 67},
    {"dir": "02_windows", "prefix": "W", "name": "Windows 서버", "start": 172, "end": 270, "expected": 64},
    {"dir": "03_web", "prefix": "WEB", "name": "웹 서비스", "start": 271, "end": 352, "expected": 26},
    {"dir": "05_network", "prefix": "N", "name": "네트워크 장비", "start": 387, "end": 466, "expected": 38},
    {"dir": "07_pc", "prefix": "PC", "name": "PC", "start": 552, "end": 592, "expected": 18},
    {"dir": "08_dbms", "prefix": "D", "name": "DBMS", "start": 593, "end": 669, "expected": 26},
]

# 페이지 머리말/꼬리말 등 잡음 라인 패턴 (제거 대상)
NOISE_PATTERNS = [
    re.compile(r"^\|\s*한국인터넷진흥원\s*\|$"),
    re.compile(r"^\d{4}\s+주요정보통신기반시설.*$"),
    # 장 제목 머리말은 항상 2자리 0-패딩 번호("01.", "02." ...)를 쓰고, 본문 내 그룹 번호는
    # 항상 1자리("1.", "2." ...)이므로 자릿수로 구분 가능
    re.compile(r"^\d{2}\.\s+\S.*$"),
    re.compile(r"^\d{1,4}\s*$"),  # 단독 페이지 번호
]

SECTION_ORDER = [
    "점검 내용",
    "점검 목적",
    "보안 위협",
    "참고",
    "점검 대상 및 판단 기준",
    "조치 방법",
    "조치 시 영향",
    "점검 및 조치 사례",
]

ITEM_HEADER_RE = re.compile(
    r"\n([A-Z]{1,4}-\d{2,3})\n\((상|중|하)\)\n([^\n>]+?)\s*>\s*(\d+)\.\s*([^\n]+)\n([^\n]+)\n개요\n",
)


def clean_page_text(raw: str) -> str:
    lines = raw.split("\n")
    kept = []
    for line in lines:
        stripped = line.strip()
        if any(p.match(stripped) for p in NOISE_PATTERNS):
            continue
        kept.append(line)
    return "\n".join(kept)


def load_category_text(doc, start_page: int, end_page: int):
    """start_page/end_page 는 가이드에 인쇄된(1-indexed) 페이지 번호, inclusive."""
    parts = []
    page_marks = []  # (문자 오프셋, 가이드 페이지 번호)
    text_acc = ""
    for guide_page in range(start_page, end_page + 1):
        pdf_index = guide_page - 1
        if pdf_index < 0 or pdf_index >= doc.page_count:
            continue
        raw = doc[pdf_index].get_text()
        cleaned = clean_page_text(raw)
        page_marks.append((len(text_acc), guide_page))
        text_acc += "\n" + cleaned + "\n"
    return text_acc, page_marks


def page_for_offset(offset: int, page_marks) -> int:
    page = page_marks[0][1] if page_marks else 0
    for off, pg in page_marks:
        if off <= offset:
            page = pg
        else:
            break
    return page


def split_sections(body: str) -> dict:
    """개요 이후 본문을 SECTION_ORDER 기준으로 분할."""
    positions = []
    for name in SECTION_ORDER:
        m = re.search(rf"\n{re.escape(name)}\n", "\n" + body)
        positions.append((m.start() if m else None, name))

    found = [(pos, name) for pos, name in positions if pos is not None]
    found.sort(key=lambda x: x[0])

    sections = {}
    padded = "\n" + body
    for i, (pos, name) in enumerate(found):
        content_start = pos + len(f"\n{name}\n")
        content_end = found[i + 1][0] if i + 1 < len(found) else len(padded)
        sections[name] = padded[content_start:content_end].strip("\n").strip()
    return sections


def parse_criteria(section_text: str):
    good = vuln = ""
    m_good = re.search(r"양호\s*[:：]\s*(.*?)(?=\n?취약\s*[:：]|\Z)", section_text, re.DOTALL)
    m_vuln = re.search(r"취약\s*[:：]\s*(.*?)\Z", section_text, re.DOTALL)
    if m_good:
        good = m_good.group(1).strip()
    if m_vuln:
        vuln = m_vuln.group(1).strip()
    # "대상"/"판단 기준" 하위 헤더 제거 후 targets 도 함께 파싱
    targets = ""
    m_targets = re.search(r"대상\n(.*?)\n판단 기준\n", section_text, re.DOTALL)
    if m_targets:
        targets = m_targets.group(1).strip()
        good = re.sub(r"^.*판단 기준\n", "", good, flags=re.DOTALL) if "판단 기준" in good else good
    return targets, good, vuln


def load_existing_tracking(out_dir: Path) -> dict:
    """기존 guide.json에서 구현 진행 상태(automation/fix/envs/deviation)만 코드별로 읽어온다.
    이 필드들은 PDF 추출 대상이 아니라 이후 check/fix 구현 단계에서 채워지는 값이므로,
    재추출 시 덮어쓰지 않고 보존한다 (guide.json을 손으로 고치지 않는다는 원칙과 양립시키기 위함)."""
    existing_path = out_dir / "guide.json"
    tracking = {}
    if existing_path.exists():
        try:
            existing = json.loads(existing_path.read_text(encoding="utf-8"))
            for it in existing.get("items", []):
                tracking[it["code"]] = {
                    "automation": it.get("automation", "manual"),
                    "fix": it.get("fix", "manual"),
                    "envs": it.get("envs", []),
                    "deviation": it.get("deviation"),
                }
        except (json.JSONDecodeError, KeyError):
            pass
    return tracking


def parse_items_for_category(doc, cat: dict, tracking: dict):
    text, page_marks = load_category_text(doc, cat["start"], cat["end"])
    matches = list(ITEM_HEADER_RE.finditer(text))
    items = []
    for i, m in enumerate(matches):
        code, severity, breadcrumb_cat, group_no, group_name, title = m.groups()
        if not code.startswith(cat["prefix"] + "-"):
            # 다른 카테고리 접두 코드가 섞여 있으면 건너뜀 (장 경계 근처 잔여 항목)
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end].strip("\n")
        sections = split_sections(body)

        content = sections.get("점검 내용", "")
        purpose = sections.get("점검 목적", "")
        threat = sections.get("보안 위협", "")
        note = sections.get("참고", "")
        crit_block = sections.get("점검 대상 및 판단 기준", "")
        remediation = sections.get("조치 방법", "")
        impact = sections.get("조치 시 영향", "")
        cases = sections.get("점검 및 조치 사례", "")

        targets, good, vuln = parse_criteria(crit_block)
        note = "" if note.strip() == "-" else note

        guide_page = page_for_offset(m.start(), page_marks)
        # 구현 진행 상태는 재추출 시에도 보존 (없으면 기본값)
        meta = tracking.get(code, {"automation": "manual", "fix": "manual", "envs": [], "deviation": None})

        items.append({
            "code": code,
            "category": cat["name"],
            "group_no": int(group_no),
            "group_name": group_name.strip(),
            "title": title.strip(),
            "severity": severity,
            "content": content,
            "purpose": purpose,
            "threat": threat,
            "note": note,
            "targets": targets,
            "criteria": {"good": good, "vuln": vuln},
            "remediation": remediation,
            "impact": impact,
            "cases": cases,
            "guide_page": guide_page,
            "guide_version": GUIDE_VERSION,
            # 작업용 메타 (check/fix 구현 단계에서 채움 — 재추출 시 보존됨, load_existing_tracking 참고)
            "automation": meta["automation"],
            "fix": meta["fix"],
            "envs": meta["envs"],
            "deviation": meta["deviation"],
        })
    return items


SEV_ORDER = {"상": 0, "중": 1, "하": 2}


def render_markdown(cat: dict, items: list) -> str:
    lines = []
    lines.append(f"# {cat['name']} 점검 항목 정리 ({cat['prefix']} 계열, 가이드 {GUIDE_VERSION}판)")
    lines.append("")
    lines.append(f"- 근거: 주요정보통신기반시설 기술적 취약점 분석·평가 방법 상세가이드 ({GUIDE_VERSION}판), p{cat['start']}~{cat['end']}")
    lines.append(f"- 총 {len(items)}개 항목 (기대값 {cat['expected']}개)")
    lines.append("- 이 문서는 `lib/extract_guide.py` 로 가이드 원문에서 자동 추출한 정리본이며, 이후 모든 check/fix 구현의 유일한 기준이다.")
    lines.append("- 가이드 원문을 그대로 사용하며, 자동화 구현을 위해 내용을 변경한 경우 해당 항목에 `deviation` 으로 표시한다 (현재는 없음).")
    lines.append("")

    groups = {}
    for it in items:
        groups.setdefault((it["group_no"], it["group_name"]), []).append(it)

    lines.append("## 항목 요약")
    lines.append("")
    lines.append("| 코드 | 중요도 | 항목명 | 분류 | 자동화 |")
    lines.append("|---|---|---|---|---|")
    for (gno, gname), gitems in sorted(groups.items()):
        for it in sorted(gitems, key=lambda x: int(x["code"].split("-")[1])):
            lines.append(f"| {it['code']} | {it['severity']} | {it['title']} | {gno}. {gname} | {it['automation']} |")
    lines.append("")

    for (gno, gname), gitems in sorted(groups.items()):
        lines.append(f"## {gno}. {gname}")
        lines.append("")
        for it in sorted(gitems, key=lambda x: int(x["code"].split("-")[1])):
            lines.append(f"### {it['code']} ({it['severity']}) {it['title']}")
            lines.append("")
            lines.append(f"- **가이드 페이지**: {it['guide_page']}")
            lines.append(f"- **대상**: {it['targets'] or '-'}")
            lines.append("")
            lines.append(f"**점검 내용**  \n{it['content']}")
            lines.append("")
            lines.append(f"**점검 목적**  \n{it['purpose']}")
            lines.append("")
            lines.append(f"**보안 위협**  \n{it['threat']}")
            lines.append("")
            if it["note"]:
                lines.append(f"**참고**  \n{it['note']}")
                lines.append("")
            lines.append(f"**판단 기준**")
            lines.append(f"- 양호: {it['criteria']['good']}")
            lines.append(f"- 취약: {it['criteria']['vuln']}")
            lines.append("")
            lines.append(f"**조치 방법**  \n{it['remediation']}")
            lines.append("")
            lines.append(f"**조치 시 영향**  \n{it['impact']}")
            lines.append("")
            lines.append(f"**점검 및 조치 사례**")
            lines.append("```")
            lines.append(it["cases"])
            lines.append("```")
            lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="특정 카테고리 폴더명만 처리 (예: 01_unix)")
    args = parser.parse_args()

    doc = pymupdf.open(str(PDF_PATH))
    report = []
    for cat in CATEGORIES:
        if args.only and cat["dir"] != args.only:
            continue
        out_dir = ROOT / cat["dir"]
        out_dir.mkdir(parents=True, exist_ok=True)
        tracking = load_existing_tracking(out_dir)
        items = parse_items_for_category(doc, cat, tracking)

        missing_fields = 0
        for it in items:
            for key in ("content", "purpose", "threat", "targets", "remediation"):
                val = it["criteria"]["good"] if key == "criteria" else it.get(key)
                if not val:
                    missing_fields += 1

        (out_dir / "guide.json").write_text(
            json.dumps({
                "category": cat["name"],
                "prefix": cat["prefix"],
                "guide_version": GUIDE_VERSION,
                "source_pages": [cat["start"], cat["end"]],
                "items": items,
            }, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        (out_dir / "guide.md").write_text(render_markdown(cat, items), encoding="utf-8")

        status = "OK" if len(items) == cat["expected"] else "MISMATCH"
        report.append((cat["dir"], len(items), cat["expected"], status, missing_fields))
        print(f"[{status}] {cat['dir']}: {len(items)}개 추출 (기대 {cat['expected']}개), 필드누락 {missing_fields}건 -> {out_dir/'guide.json'}")

    mismatches = [r for r in report if r[3] != "OK"]
    if mismatches:
        print("\n경고: 항목 수가 기대값과 다른 카테고리가 있습니다:", mismatches, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
