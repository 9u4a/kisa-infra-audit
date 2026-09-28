"""lib/report_common.py — 분석자 PC 전용 Python 카테고리(05_network 등)의 공용 결과/보고서 모듈.

sh/PowerShell 쪽의 lib/common.sh, lib/Common.psm1 과 동일한 역할(결과 JSON 조립, CSV/summary
작성, report.html 렌더링)을 Python 으로 제공한다. 대상 호스트에는 배치하지 않는다(분석자 PC에서만
실행되는 스크립트가 import 한다).
"""
from __future__ import annotations

import csv
import datetime
import json
import os

GUIDE_VERSION = "2026"

STATUS_LABEL_KO = {"VULN": "취약", "MANUAL": "수동점검", "ERROR": "오류", "NA": "해당없음", "GOOD": "양호"}
STATUS_ORDER = {"VULN": 0, "MANUAL": 1, "ERROR": 2, "NA": 3, "GOOD": 4}
SEVERITY_ORDER = {"상": 0, "중": 1, "하": 2}


def get_tool_version(repo_root: str) -> str:
    path = os.path.join(repo_root, "VERSION")
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return "0.0.0-unknown"


def _sort_key(item: dict) -> tuple:
    return (STATUS_ORDER.get(item.get("status"), 9), SEVERITY_ORDER.get(item.get("severity", ""), 9))


def write_result_json(path: str, items: list[dict], category: str, host: str, env: str, tool_version: str) -> None:
    obj = {
        "tool_version": tool_version,
        "guide_version": GUIDE_VERSION,
        "category": category,
        "host": host,
        "env": env,
        "generated_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "items": sorted(
            [{"code": it["code"], "status": it["status"], "detail": it["detail"], "evidence": it.get("evidence", "")} for it in items],
            key=_sort_key,
        ),
    }
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def write_csv(path: str, items: list[dict], guide_by_code: dict) -> None:
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["code", "severity", "group", "title", "status", "detail"])
        for it in sorted(items, key=_sort_key):
            meta = guide_by_code.get(it["code"], {})
            w.writerow([it["code"], meta.get("severity", ""), meta.get("group_no", ""), meta.get("title", ""), it["status"], it["detail"]])


def render_report_html(lib_dir: str, guide_json_path: str, result_json_path: str, out_html_path: str) -> None:
    """lib/report/{head,mid,tail}.html + guide.json + result.json 을 순서대로 이어붙여 report.html 생성."""
    parts = [
        os.path.join(lib_dir, "report", "head.html"),
        guide_json_path,
        os.path.join(lib_dir, "report", "mid.html"),
        result_json_path,
        os.path.join(lib_dir, "report", "tail.html"),
    ]
    content = "".join(open(p, encoding="utf-8").read() for p in parts)
    with open(out_html_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def write_summary(path: str, category: str, host: str, env: str, counts: dict) -> str:
    total = sum(counts.values())
    base = counts.get("VULN", 0) + counts.get("GOOD", 0)
    rate = int(counts.get("GOOD", 0) * 100 / base) if base else 0
    lines = [
        f"=== {category} 진단 요약 ===",
        f"호스트   : {host}",
        f"환경     : {env}",
        f"시각     : {datetime.datetime.now():%Y-%m-%d %H:%M:%S}",
        f"총 항목  : {total}",
        "----------------------------",
        f"취약         {counts.get('VULN', 0)}",
        f"수동점검     {counts.get('MANUAL', 0)}",
        f"오류         {counts.get('ERROR', 0)}",
        f"해당없음     {counts.get('NA', 0)}",
        f"양호         {counts.get('GOOD', 0)}",
        "----------------------------",
        f"준수율(취약/양호 중): {rate}%",
    ]
    text = "\n".join(lines) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return text


def progress_show(current: int, total: int, code: str, title: str, status: str) -> None:
    pct = int(current * 100 / total) if total else 0
    filled = pct // 5
    bar = ("#" * filled).ljust(20, ".")
    label = STATUS_LABEL_KO.get(status, status)
    title_disp = (title[:38] + "..") if len(title) > 40 else title
    print(f"[{current:3d}/{total:3d}] {pct:3d}% [{bar}] {code:<8} {title_disp:<40} {label}")
