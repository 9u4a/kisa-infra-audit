#!/usr/bin/env python3
"""lib/policy_draft.py — 진단 결과(result.json)로 조치 정책 파일 초안을 만든다 (분석자 PC 전용, Python 3.10+, 표준 라이브러리만).

1.7.0 값 지정 조치: fix=param 항목(U-07 계정 잠금, U-23 SUID 제거 등)은 "무엇을" 바꿀지 사람이 정해 정책 파일 호스트 구역에
`코드.키 = 값` 으로 적는다. 이 스크립트는 그 판단을 돕는 초안만 만든다 - 진단 증적의 `[candidates]` 줄(check 가 남긴 후보 목록)을
호스트 구역마다 값 줄로 적되 **모두 주석 상태**로 둔다. 승인 코드 줄도 주석이다. 사람이 고르지(주석을 풀지) 않으면 아무것도
적용되지 않는다. --approver 를 주지 않으면 approver= 가 비어 있어 파서가 거부하므로, 승인자 검토 없이는 쓸 수 없다.

사용법:
  python lib/policy_draft.py <result.json>... [-o policy.txt] [--approver 이름] [--days 30]
  - 여러 호스트의 결과를 함께 주면 호스트마다 [host:이름] 구역을 만든다(카테고리는 모두 같아야 함, 08 은 엔진이 달라도 됨).
  - 출력 기본은 표준출력. 파일로 쓸 때는 UTF-8(BOM 없음)·LF.
"""
from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))
import fix_policy  # noqa: E402  (lib/fix_policy.py - 원복·영향 머리말)

CAND = "[candidates] "


def category_dirs() -> dict[str, tuple[str, Path]]:
    """result.json category 값(guide.json category, 예: UNIX) → (카테고리 번호, 폴더)."""
    out = {}
    for g in sorted(ROOT.glob("[0-9][0-9]_*/guide.json")):
        name = json.loads(g.read_text(encoding="utf-8"))["category"]
        out[name] = (g.parent.name[:2], g.parent)
    return out


def needs_irreversible(cat_dir: Path, code: str) -> bool:
    """그 코드의 조치 파일(계열·엔진 하위 폴더 포함) 중 하나라도 원복·영향 머리말이 있으면 :irreversible 이 필요하다."""
    return any(fix_policy.impact_note(str(f)) for f in (cat_dir / "fixes").rglob(f"{code}.*"))


def candidates(evidence: str) -> list[str]:
    for ln in (evidence or "").splitlines():
        if ln.startswith(CAND):
            return [v.strip() for v in ln[len(CAND):].split(",") if v.strip()]
    return []


def build(results: list[Path], approver: str, days: int, today: datetime.date) -> str:
    cats = category_dirs()
    loaded = []
    for p in results:
        try:
            r = json.loads(p.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError) as e:
            raise SystemExit(f"오류: {p} 를 읽을 수 없음 ({e})")
        if r.get("category") not in cats:
            raise SystemExit(f"오류: {p} 의 category '{r.get('category')}' 를 알 수 없음")
        loaded.append((p, r))
    nums = {cats[r["category"]][0] for _, r in loaded}
    if len(nums) != 1:
        raise SystemExit(f"오류: 결과의 카테고리가 여럿임({', '.join(sorted(nums))}) - 정책 파일은 카테고리마다 따로 만든다")
    num = nums.pop()
    cat_dir = cats[loaded[0][1]["category"]][1]
    guide = {i["code"]: i for i in json.loads((cat_dir / "guide.json").read_text(encoding="utf-8"))["items"]}

    # 승인 후보: 어느 호스트에서든 VULN 이거나, param 항목이면서 후보가 있는 것
    want: dict[str, str] = {}
    hosts: dict[str, list[str]] = {}
    for p, r in loaded:
        host = str(r.get("host") or p.parent.name)
        lines = hosts.setdefault(host, [])
        for it in r.get("items", []):
            code, st = it.get("code"), it.get("status")
            g = guide.get(code)
            if not g:
                continue
            grade = g.get("fix", "manual")
            if grade == "param":
                cand = candidates(it.get("evidence", ""))
                keys = [k.strip() for k in str(g.get("fix_params") or "").split(",") if k.strip()]
                if st in ("VULN", "MANUAL") and cand and keys:
                    want.setdefault(code, f"param - {g.get('title', '')}")
                    lines.append(f"# {code} 후보({st}): {', '.join(cand)}  ← 바꿀 대상만 남기고 아래 줄 주석 해제")
                    lines.append(f"# {code}.{keys[0]} = {', '.join(cand)}")
            elif st == "VULN" and grade in ("auto", "confirm"):
                want.setdefault(code, f"{grade} - {g.get('title', '')}")
    expires = today + datetime.timedelta(days=days)
    out = [
        f"# 조치 정책 초안 - lib/policy_draft.py 가 {today.isoformat()} 에 결과 {len(loaded)}개로 생성. 승인자가 검토하고 고친다.",
        "# 승인 줄·값 줄은 모두 주석 상태다. 적용할 것만 주석(#)을 지운다 - 지우지 않으면 아무것도 적용되지 않는다.",
        "# 값 지정 조치(param)는 승인 줄과 호스트 구역의 값 줄이 둘 다 있어야 적용된다. 형식: docs/USAGE.md '조치 정책 모드'",
        f"category={num}",
        f"expires={expires.isoformat()}",
        f"approver={approver}",
        "",
    ]
    for code in sorted(want, key=lambda c: (c.split("-")[0], int(c.split("-")[1]))):
        flag = ":irreversible" if needs_irreversible(cat_dir, code) else ""
        out.append(f"# {code}{flag}".ljust(24) + f"# {want[code]}")
    for host in sorted(hosts):
        out += ["", f"[host:{host}]", *hosts[host]]
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="진단 결과로 조치 정책 파일 초안 만들기(모든 줄 주석 상태)")
    ap.add_argument("results", nargs="+", type=Path, help="result.json (여러 개 가능, 같은 카테고리)")
    ap.add_argument("-o", "--output", type=Path, help="출력 파일(기본: 표준출력)")
    ap.add_argument("--approver", default="", help="승인자 이름(비우면 approver= 가 비어 파서가 거부 - 검토 강제)")
    ap.add_argument("--days", type=int, default=30, help="유효기간(오늘부터 일 수, 기본 30)")
    a = ap.parse_args()
    text = build(a.results, a.approver.strip(), a.days, datetime.date.today())
    if a.output:
        with open(a.output, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"생성: {a.output}")
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
