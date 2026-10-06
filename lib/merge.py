#!/usr/bin/env python3
"""lib/merge.py — 다중 호스트 결과 병합 (분석자 PC 전용, Python 3.10+).

같은 카테고리를 여러 호스트에서 각각 run.*로 진단한 뒤 생긌 result.json 여러 개를 모아,
호스트별 준수율과 전사(全社) 공통 취약 항목 순위를 한 번에 보는 병합 보고서를 만든다. 개별
호스트의 report.html(단일 호스트 전용)과는 별개의 산출물이며, 이 스크립트는 대상 시스템에
전혀 접근하지 않고 이미 생성된 result.json 파일들만 읽는다(분석자 PC에서만 실행).

사용법:
  python lib/merge.py output/*/result.json -o output/merged
  python lib/merge.py --dir output -c 01 -o output/merged_unix   # output/ 아래 모든 01_unix 결과 자동 탐색
"""
from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import sys
from datetime import datetime

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

STATUS_ORDER = {"VULN": 1, "MANUAL": 2, "ERROR": 3, "NA": 4, "GOOD": 5}
STATUS_KO = {"VULN": "취약", "MANUAL": "수동점검", "ERROR": "오류", "NA": "해당없음", "GOOD": "양호"}


def discover_results(dir_path: str, category_num: str | None) -> list[str]:
    pattern = os.path.join(dir_path, "*", "result.json")
    paths = sorted(glob.glob(pattern))
    if category_num:
        out = []
        for p in paths:
            folder = os.path.basename(os.path.dirname(p))
            # 출력 폴더명 규칙: <host>_<카테고리번호>_<YYYYMMDD-HHMMSS>[_fix_<ts>]
            parts = folder.split("_")
            if len(parts) >= 2 and parts[-2] == category_num:
                out.append(p)
            elif f"_{category_num}_" in folder:
                out.append(p)
        return out
    return paths


def load_results(paths: list[str]) -> list[dict]:
    loaded = []
    for p in paths:
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            print(f"경고: {p} 를 읽을 수 없어 건너뜀: {e}", file=sys.stderr)
            continue
        data["_path"] = p
        loaded.append(data)
    return loaded


def write_csv(path: str, results: list[dict], guide_by_code: dict) -> None:
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["host", "code", "severity", "group", "title", "status", "detail"])
        for r in results:
            host = r.get("host", "unknown")
            for it in r.get("items", []):
                meta = guide_by_code.get(it["code"], {})
                w.writerow([
                    host, it["code"], meta.get("severity", ""), meta.get("group_name", ""),
                    meta.get("title", ""), it["status"], it.get("detail", ""),
                ])


def per_host_stats(results: list[dict]) -> list[dict]:
    rows = []
    for r in results:
        counts = {"VULN": 0, "MANUAL": 0, "ERROR": 0, "NA": 0, "GOOD": 0}
        for it in r.get("items", []):
            counts[it["status"]] = counts.get(it["status"], 0) + 1
        base = counts["VULN"] + counts["GOOD"]
        rate = round(counts["GOOD"] * 100 / base) if base else None
        rows.append({"host": r.get("host", "unknown"), "env": r.get("env", ""), "counts": counts, "rate": rate})
    rows.sort(key=lambda x: (x["rate"] if x["rate"] is not None else -1))
    return rows


def per_item_stats(results: list[dict], guide_by_code: dict) -> list[dict]:
    agg: dict[str, dict] = {}
    for r in results:
        for it in r.get("items", []):
            code = it["code"]
            a = agg.setdefault(code, {"code": code, "vuln": 0, "applicable": 0})
            if it["status"] in ("VULN", "GOOD"):
                a["applicable"] += 1
                if it["status"] == "VULN":
                    a["vuln"] += 1
    rows = []
    for code, a in agg.items():
        meta = guide_by_code.get(code, {})
        rate = round(a["vuln"] * 100 / a["applicable"]) if a["applicable"] else 0
        rows.append({
            "code": code, "title": meta.get("title", code), "severity": meta.get("severity", ""),
            "vuln": a["vuln"], "applicable": a["applicable"], "vuln_rate": rate,
        })
    rows.sort(key=lambda x: (-x["vuln"], -x["vuln_rate"]))
    return rows


def write_summary(path: str, category: str, host_rows: list[dict], item_rows: list[dict]) -> str:
    lines = []
    lines.append(f"=== {category} 다중 호스트 병합 요약 (호스트 {len(host_rows)}개) ===")
    lines.append(f"생성 시각: {datetime.now():%Y-%m-%d %H:%M:%S}")
    lines.append("-" * 72)
    lines.append("[호스트별 준수율 - 낮은 순]")
    for h in host_rows:
        rate_s = f"{h['rate']}%" if h["rate"] is not None else "N/A"
        c = h["counts"]
        lines.append(
            f"  {h['host']:<24} 준수율={rate_s:>5}  취약={c['VULN']:>3} 수동={c['MANUAL']:>3} "
            f"오류={c['ERROR']:>3} 해당없음={c['NA']:>3} 양호={c['GOOD']:>3}"
        )
    lines.append("-" * 72)
    lines.append("[전사 공통 취약 항목 - 취약 호스트 수 많은 순, 상위 20개]")
    for it in item_rows[:20]:
        if it["vuln"] == 0:
            continue
        lines.append(
            f"  {it['code']:<8} ({it['severity']}) {it['title']:<40} "
            f"취약 {it['vuln']}/{it['applicable']}개 호스트 ({it['vuln_rate']}%)"
        )
    text = "\n".join(lines) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return text


_HTML_TEMPLATE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>다중 호스트 병합 보고서</title>
<style>
  :root{{--bg:#f5f6f8;--panel:#fff;--text:#1a1d23;--muted:#6b7280;--border:#e3e5e9;
    --vuln:#dc2626;--manual:#d97706;--error:#c026d3;--na:#9ca3af;--good:#16a34a;--accent:#2563eb;}}
  @media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{--bg:#14161a;--panel:#1c1f26;
    --text:#e8eaed;--muted:#9aa1ab;--border:#2c313a;--vuln:#f87171;--manual:#fbbf24;--error:#e879f9;
    --na:#6b7280;--good:#4ade80;--accent:#60a5fa;}}}}
  *{{box-sizing:border-box;}}
  body{{margin:0;background:var(--bg);color:var(--text);font-family:-apple-system,"Segoe UI",Malgun Gothic,sans-serif;font-size:14px;}}
  .wrap{{max-width:1080px;margin:0 auto;padding:20px 16px 60px;}}
  h1{{font-size:20px;}} h2{{font-size:15px;color:var(--muted);margin-top:28px;}}
  .meta{{color:var(--muted);font-size:12.5px;}}
  table{{width:100%;border-collapse:collapse;background:var(--panel);border:1px solid var(--border);border-radius:10px;overflow:hidden;margin-top:10px;}}
  thead th{{text-align:left;font-size:12px;color:var(--muted);text-transform:uppercase;padding:10px 12px;border-bottom:1px solid var(--border);}}
  tbody td{{padding:8px 12px;border-bottom:1px solid var(--border);}}
  tbody tr:last-child td{{border-bottom:none;}}
  .code{{font-family:ui-monospace,Consolas,monospace;font-weight:600;}}
  .rate{{font-weight:700;}}
  footer{{color:var(--muted);font-size:12px;margin-top:24px;text-align:center;}}
</style>
</head>
<body><div class="wrap">
<h1>다중 호스트 병합 보고서 - {category}</h1>
<div class="meta">호스트 {host_count}개 / 생성 시각 {generated_at}</div>

<h2>호스트별 준수율 (낮은 순)</h2>
<table><thead><tr><th>호스트</th><th>환경</th><th>준수율</th><th>취약</th><th>수동점검</th><th>오류</th><th>해당없음</th><th>양호</th></tr></thead>
<tbody>{host_rows}</tbody></table>

<h2>전사 공통 취약 항목 (취약 호스트 수 많은 순)</h2>
<table><thead><tr><th>코드</th><th>중요도</th><th>항목명</th><th>취약 호스트</th><th>취약률</th></tr></thead>
<tbody>{item_rows}</tbody></table>

<footer>kisa-infra-audit lib/merge.py</footer>
</div></body></html>
"""


def render_html(path: str, category: str, host_rows: list[dict], item_rows: list[dict]) -> None:
    def rate_color(rate):
        if rate is None:
            return "var(--muted)"
        if rate >= 90:
            return "var(--good)"
        if rate >= 70:
            return "var(--manual)"
        return "var(--vuln)"

    host_html = []
    for h in host_rows:
        rate_s = f"{h['rate']}%" if h["rate"] is not None else "N/A"
        c = h["counts"]
        host_html.append(
            f"<tr><td>{h['host']}</td><td>{h['env']}</td>"
            f"<td class=\"rate\" style=\"color:{rate_color(h['rate'])}\">{rate_s}</td>"
            f"<td>{c['VULN']}</td><td>{c['MANUAL']}</td><td>{c['ERROR']}</td><td>{c['NA']}</td><td>{c['GOOD']}</td></tr>"
        )
    item_html = []
    for it in item_rows:
        if it["vuln"] == 0:
            continue
        item_html.append(
            f"<tr><td class=\"code\">{it['code']}</td><td>{it['severity']}</td><td>{it['title']}</td>"
            f"<td>{it['vuln']}/{it['applicable']}</td>"
            f"<td class=\"rate\" style=\"color:{rate_color(100 - it['vuln_rate'])}\">{it['vuln_rate']}%</td></tr>"
        )
    html = _HTML_TEMPLATE.format(
        category=category,
        host_count=len(host_rows),
        generated_at=f"{datetime.now():%Y-%m-%d %H:%M:%S}",
        host_rows="".join(host_html) or "<tr><td colspan=8>데이터 없음</td></tr>",
        item_rows="".join(item_html) or "<tr><td colspan=5>취약 항목 없음</td></tr>",
    )
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(html)


def main() -> None:
    parser = argparse.ArgumentParser(description="다중 호스트 result.json 병합", add_help=True)
    parser.add_argument("paths", nargs="*", help="병합할 result.json 경로들(glob 가능)")
    parser.add_argument("--dir", dest="dirpath", help="output/ 와 같이 <host>_<cat>_<ts>/result.json 들을 담은 상위 폴더")
    parser.add_argument("-c", "--category", dest="category_num", help="--dir 사용 시 카테고리 번호로 필터 (예: 01, 08)")
    parser.add_argument("-o", "--out", required=True, help="병합 결과 출력 경로")
    args = parser.parse_args()

    paths: list[str] = []
    for p in args.paths:
        paths.extend(sorted(glob.glob(p)) if any(ch in p for ch in "*?[") else [p])
    if args.dirpath:
        paths.extend(discover_results(args.dirpath, args.category_num))
    paths = sorted(set(paths))

    if not paths:
        print("오류: 병합할 result.json 을 찾지 못했습니다.", file=sys.stderr)
        sys.exit(2)

    results = load_results(paths)
    if not results:
        print("오류: 유효한 result.json 이 없습니다.", file=sys.stderr)
        sys.exit(2)

    categories = {r.get("category", "") for r in results}
    if len(categories) > 1:
        print(f"경고: 서로 다른 카테고리가 섞여 있습니다: {categories} - 그대로 병합을 진행합니다.", file=sys.stderr)
    category = next(iter(categories), "unknown")

    # guide.json 메타데이터(제목/중요도/분류)는 결과 폴더가 아니라 각 카테고리 폴더에 있으므로,
    # result.json 들이 가리키는 카테고리 폴더를 추정해 읽는다 - 못 찾으면 코드만으로 표시한다.
    guide_by_code: dict = {}
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for entry in os.listdir(repo_root):
        guide_path = os.path.join(repo_root, entry, "guide.json")
        if os.path.isfile(guide_path):
            try:
                with open(guide_path, encoding="utf-8") as f:
                    g = json.load(f)
                if g.get("category") == category or g.get("prefix") and any(
                    it["code"].startswith(g["prefix"] + "-") for it in results[0].get("items", [])
                ):
                    guide_by_code = {it["code"]: it for it in g["items"]}
                    break
            except (OSError, json.JSONDecodeError):
                continue

    os.makedirs(args.out, exist_ok=True)
    write_csv(os.path.join(args.out, "merged.csv"), results, guide_by_code)
    host_rows = per_host_stats(results)
    item_rows = per_item_stats(results, guide_by_code)
    summary_text = write_summary(os.path.join(args.out, "merged_summary.txt"), category, host_rows, item_rows)
    render_html(os.path.join(args.out, "merged_report.html"), category, host_rows, item_rows)

    print(summary_text)
    print(f"병합 결과: {args.out} (merged.csv, merged_summary.txt, merged_report.html)")


if __name__ == "__main__":
    main()
