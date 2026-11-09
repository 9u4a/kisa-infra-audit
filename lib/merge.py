#!/usr/bin/env python3
"""lib/merge.py — 다중 호스트 결과 병합·조치 전후 비교 (분석자 PC 전용, Python 3.10+).

같은 카테고리를 여러 호스트에서 각각 run.*로 진단한 뒤 생긴 result.json 여러 개를 모아,
호스트별 준수율과 전사(全社) 공통 취약 항목 순위를 한 번에 보는 병합 보고서를 만든다. 개별
호스트의 report.html(단일 호스트 전용)과는 별개의 산출물이며, 이 스크립트는 대상 시스템에
전혀 접근하지 않고 이미 생성된 result.json 파일들만 읽는다(분석자 PC에서만 실행).

1.6.0 G-04 --diff: 조치 전·후 결과를 호스트+카테고리(+환경)+코드로 맞춰 신규 취약·조치 완료·미조치·확인 필요·
변화 없음 양호로 분류한다. G-05 --verdicts: 보고서에서 내려받은 manual_verdicts.json(사람 판정)을 병합·비교에
반영한다 - result.json 은 바꾸지 않고, 원래 MANUAL 이었다는 것을 보존해 "사람 판정"으로 구분 표시한다.

경로 인자는 result.json 파일, glob, 결과 폴더(<host>_<cat>_<ts>/), 또는 그런 폴더들을 담은 상위 폴더(output/)
모두 받는다(상위 폴더는 -c 로 카테고리를 거를 수 있다). 같은 호스트(+카테고리·환경)의 결과가 여럿이면 가장
최근(generated_at) 것만 쓴다.

사용법:
  python lib/merge.py output/*/result.json -o output/merged
  python lib/merge.py --dir output -c 01 -o output/merged_unix   # output/ 아래 모든 01_unix 결과 자동 탐색
  python lib/merge.py output/before -c 01 --verdicts mv_web01.json mv_web02.json -o output/merged
  python lib/merge.py --diff output/before output/after -c 01 -o output/diff          # 전·후 폴더 하나씩
  python lib/merge.py --diff --before b1/result.json b2/ --after a1/ a2/ -o output/diff  # 여러 개
"""
from __future__ import annotations

import argparse
import csv
import glob
import html
import json
import os
import sys
from datetime import datetime

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

STATUS_ORDER = {"VULN": 1, "MANUAL": 2, "ERROR": 3, "NA": 4, "GOOD": 5}
STATUS_KO = {"VULN": "취약", "MANUAL": "수동점검", "ERROR": "오류", "NA": "해당없음", "GOOD": "양호"}
SEV_ORDER = {"상": 0, "중": 1, "하": 2}
VERDICT_VALUES = ("VULN", "GOOD")

# 비교 분류(표시 순서 = 정렬 순서). 신규 취약이 맨 위.
DIFF_CLASSES = [
    ("NEW_VULN", "신규 취약"),
    ("FIXED", "조치 완료"),
    ("UNFIXED", "미조치"),
    ("CHECK", "확인 필요"),
    ("UNCHANGED_GOOD", "변화 없음 양호"),
]
DIFF_KO = dict(DIFF_CLASSES)


def warn(msg: str) -> None:
    print(f"경고: {msg}", file=sys.stderr)


# ---- 결과 수집 ---------------------------------------------------------------------------------------------
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


def expand_paths(args_paths: list[str], category_num: str | None) -> list[str]:
    """파일·glob·결과 폴더·상위 폴더를 result.json 경로 목록으로 펼친다."""
    out: list[str] = []
    for p in args_paths:
        cands = sorted(glob.glob(p)) if any(ch in p for ch in "*?[") else [p]
        for c in cands:
            if os.path.isdir(c):
                if os.path.isfile(os.path.join(c, "result.json")):
                    out.append(os.path.join(c, "result.json"))
                else:
                    found = discover_results(c, category_num)
                    if not found:
                        warn(f"{c} 아래에서 result.json 을 찾지 못함")
                    out.extend(found)
            else:
                out.append(c)
    return sorted(set(out))


def load_results(paths: list[str]) -> list[dict]:
    loaded = []
    for p in paths:
        try:
            # 1.5.0 C1: 증적에 UTF-8 이 아닌 바이트(EUC-KR 등)가 섞인 예전 버전의 결과도 병합한다 - 예전에는
            # UnicodeDecodeError 로 병합 전체가 중단됐다. 잘못된 바이트는 U+FFFD 로 바꿔 읽는다.
            with open(p, encoding="utf-8-sig", errors="replace") as f:
                data = json.load(f)
        except (OSError, ValueError) as e:
            print(f"경고: {p} 를 읽을 수 없어 건너뜀: {e}", file=sys.stderr)
            continue
        data["_path"] = p
        loaded.append(data)
    return dedupe_hosts(loaded)


def dedupe_hosts(results: list[dict]) -> list[dict]:
    """같은 호스트(+카테고리·환경)를 여러 번 진단한 결과가 섞이면 가장 최근(generated_at) 것만 남긴다.
    예전에는 모두 합산해 호스트 수·항목별 취약 수가 부풀었다(실무 적용 검증 P-22). 뺀 결과는 경고로 알린다."""
    latest: dict[tuple, dict] = {}
    for r in results:
        key = (r.get("host", "unknown"), r.get("category", ""), r.get("env", ""))
        cur = latest.get(key)
        if cur is None or str(r.get("generated_at", "")) > str(cur.get("generated_at", "")):
            if cur is not None:
                print(f"경고: 같은 호스트의 이전 결과를 제외함: {cur['_path']}", file=sys.stderr)
            latest[key] = r
        else:
            print(f"경고: 같은 호스트의 이전 결과를 제외함: {r['_path']}", file=sys.stderr)
    return list(latest.values())


def load_guide(results: list[dict]) -> dict:
    """guide.json 메타데이터(제목/중요도/분류)는 결과 폴더가 아니라 각 카테고리 폴더에 있으므로,
    result.json 들이 가리키는 카테고리 폴더를 추정해 읽는다 - 못 찾으면 코드만으로 표시한다."""
    if not results:
        return {}
    category = results[0].get("category", "")
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for entry in sorted(os.listdir(repo_root)):
        guide_path = os.path.join(repo_root, entry, "guide.json")
        if os.path.isfile(guide_path):
            try:
                with open(guide_path, encoding="utf-8-sig") as f:
                    g = json.load(f)
                if g.get("category") == category or g.get("prefix") and any(
                    it["code"].startswith(g["prefix"] + "-") for it in results[0].get("items", [])
                ):
                    return {it["code"]: it for it in g["items"]}
            except (OSError, json.JSONDecodeError):
                continue
    return {}


# ---- 사람 판정(G-05) ---------------------------------------------------------------------------------------
def load_verdict_files(paths: list[str]) -> list[dict]:
    out = []
    for p in paths:
        try:
            with open(p, encoding="utf-8-sig") as f:
                data = json.load(f)
        except (OSError, ValueError) as e:
            warn(f"판정 파일 {p} 를 읽을 수 없어 무시: {e}")
            continue
        if not isinstance(data, dict) or not isinstance(data.get("verdicts"), list):
            warn(f"판정 파일 {p} 형식 오류(verdicts 목록 없음) - 무시")
            continue
        data["_path"] = p
        out.append(data)
    return out


def apply_verdicts(results: list[dict], verdict_files: list[dict]) -> int:
    """판정 파일을 결과 항목에 붙인다(item["_human"]). result.json 원본 값(status)은 바꾸지 않는다.
    판정 파일은 host(대소문자 무시)·category·generated_from(= result.json generated_at)이 모두 같은 결과에만
    적용한다 - 조치 전·후 결과가 함께 있어도 어느 쪽 판정인지 섞이지 않는다. 적용한 판정 수를 돌려준다."""
    applied = 0
    for vf in verdict_files:
        host = str(vf.get("host", ""))
        cat = str(vf.get("category", ""))
        gen = str(vf.get("generated_from", ""))
        same_hc = [r for r in results if str(r.get("host", "")).lower() == host.lower() and str(r.get("category", "")) == cat]
        if not same_hc:
            warn(f"판정 파일 {vf['_path']}: 호스트/카테고리({host}/{cat})가 맞는 결과가 없어 무시")
            continue
        targets = [r for r in same_hc if str(r.get("generated_at", "")) == gen]
        if not targets:
            have = ", ".join(sorted(str(r.get("generated_at", "")) for r in same_hc))
            warn(f"판정 파일 {vf['_path']}: generated_from={gen} 인 {host} 결과가 없어 무시(있는 결과: {have})")
            continue
        for r in targets:
            items = {it.get("code"): it for it in r.get("items", [])}
            for v in vf["verdicts"]:
                if not isinstance(v, dict):
                    warn(f"판정 파일 {vf['_path']}: 형식 오류 항목 무시: {v!r}")
                    continue
                code = str(v.get("code", ""))
                verdict = str(v.get("verdict", ""))
                reason = str(v.get("reason", "")).strip()
                it = items.get(code)
                if it is None:
                    warn(f"판정 파일 {vf['_path']}: {host} 결과에 없는 코드 {code} - 무시")
                    continue
                if it.get("status") != "MANUAL":
                    warn(f"판정 파일 {vf['_path']}: {host} {code} 는 MANUAL 이 아님({it.get('status')}) - 무시")
                    continue
                if verdict not in VERDICT_VALUES:
                    warn(f"판정 파일 {vf['_path']}: {host} {code} verdict={verdict!r} 는 VULN/GOOD 가 아님 - 무시")
                    continue
                if not reason:
                    warn(f"판정 파일 {vf['_path']}: {host} {code} 사유(reason)가 비어 있음 - 무시")
                    continue
                new = {"verdict": verdict, "reason": reason, "judged_by": str(v.get("judged_by", "")).strip(),
                       "judged_at": str(v.get("judged_at", "")), "file": vf["_path"]}
                old = it.get("_human")
                if old is not None:
                    keep_new = new["judged_at"] >= old["judged_at"]
                    warn(f"{host} {code} 판정이 여러 파일에 있음 - judged_at 이 늦은 "
                         f"{(new if keep_new else old)['file']} 를 씀")
                    if not keep_new:
                        continue
                else:
                    applied += 1
                it["_human"] = new
    return applied


def eff_status(it: dict | None) -> str | None:
    """최종 상태 - 사람 판정이 있으면 그 판정, 없으면 자동 판정."""
    if it is None:
        return None
    h = it.get("_human")
    return h["verdict"] if h else it.get("status")


def status_label(it: dict | None) -> str:
    if it is None:
        return "(없음)"
    h = it.get("_human")
    if h:
        return f"{STATUS_KO[h['verdict']]}(사람 판정, 원래 수동점검)"
    return STATUS_KO.get(it.get("status"), str(it.get("status")))


# ---- 병합 -------------------------------------------------------------------------------------------------
def write_csv(path: str, results: list[dict], guide_by_code: dict) -> None:
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        # status = 최종 상태(사람 판정 반영), original_status = result.json 원래 값
        w.writerow(["host", "code", "severity", "group", "title", "status", "detail",
                    "original_status", "judged", "verdict_reason", "judged_by", "judged_at"])
        for r in results:
            host = r.get("host", "unknown")
            for it in r.get("items", []):
                meta = guide_by_code.get(it["code"], {})
                h = it.get("_human") or {}
                w.writerow([
                    host, it["code"], meta.get("severity", ""), meta.get("group_name", ""),
                    meta.get("title", ""), eff_status(it), it.get("detail", ""),
                    it["status"], "human" if h else "auto", h.get("reason", ""), h.get("judged_by", ""), h.get("judged_at", ""),
                ])


def per_host_stats(results: list[dict]) -> list[dict]:
    rows = []
    for r in results:
        counts = {"VULN": 0, "MANUAL": 0, "ERROR": 0, "NA": 0, "GOOD": 0}
        human = 0
        for it in r.get("items", []):
            s = eff_status(it)
            counts[s] = counts.get(s, 0) + 1
            human += 1 if it.get("_human") else 0
        base = counts["VULN"] + counts["GOOD"]
        # summary.txt·report.html 과 같은 버림 - round() 는 은행가 반올림이라 74.5% 가 74, report.html 은 75 였다(P-22)
        rate = counts["GOOD"] * 100 // base if base else None
        rows.append({"host": r.get("host", "unknown"), "env": r.get("env", ""), "counts": counts, "rate": rate, "human": human})
    rows.sort(key=lambda x: (x["rate"] if x["rate"] is not None else -1))
    return rows


def per_item_stats(results: list[dict], guide_by_code: dict) -> list[dict]:
    agg: dict[str, dict] = {}
    for r in results:
        for it in r.get("items", []):
            code = it["code"]
            a = agg.setdefault(code, {"code": code, "vuln": 0, "applicable": 0})
            s = eff_status(it)
            if s in ("VULN", "GOOD"):
                a["applicable"] += 1
                if s == "VULN":
                    a["vuln"] += 1
    rows = []
    for code, a in agg.items():
        meta = guide_by_code.get(code, {})
        rate = a["vuln"] * 100 // a["applicable"] if a["applicable"] else 0
        rows.append({
            "code": code, "title": meta.get("title", code), "severity": meta.get("severity", ""),
            "vuln": a["vuln"], "applicable": a["applicable"], "vuln_rate": rate,
        })
    rows.sort(key=lambda x: (-x["vuln"], -x["vuln_rate"]))
    return rows


def human_rows(results: list[dict], guide_by_code: dict) -> list[dict]:
    rows = []
    for r in results:
        for it in r.get("items", []):
            h = it.get("_human")
            if h:
                meta = guide_by_code.get(it["code"], {})
                rows.append({"host": r.get("host", "unknown"), "code": it["code"], "title": meta.get("title", it["code"]), **h})
    rows.sort(key=lambda x: (x["host"], x["code"]))
    return rows


def write_summary(path: str, category: str, host_rows: list[dict], item_rows: list[dict], hrows: list[dict] | None = None) -> str:
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
            + (f"  (사람 판정 {h['human']}건 반영)" if h.get("human") else "")
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
    if hrows:
        lines.append("-" * 72)
        lines.append(f"[사람 판정 반영 {len(hrows)}건 - 원래 수동점검(result.json 은 그대로)]")
        for h in hrows:
            lines.append(f"  {h['host']:<24} {h['code']:<8} {STATUS_KO[h['verdict']]}  사유: {h['reason']}  "
                         f"(판정자 {h['judged_by'] or '-'}, {h['judged_at'] or '-'})")
    text = "\n".join(lines) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return text


# ---- HTML 공통 ---------------------------------------------------------------------------------------------
_CSS = """
  :root{--bg:#f5f6f8;--panel:#fff;--text:#1a1d23;--muted:#6b7280;--border:#e3e5e9;
    --vuln:#dc2626;--manual:#d97706;--error:#c026d3;--na:#9ca3af;--good:#16a34a;--accent:#2563eb;}
  @media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#14161a;--panel:#1c1f26;
    --text:#e8eaed;--muted:#9aa1ab;--border:#2c313a;--vuln:#f87171;--manual:#fbbf24;--error:#e879f9;
    --na:#6b7280;--good:#4ade80;--accent:#60a5fa;}}
  *{box-sizing:border-box;}
  body{margin:0;background:var(--bg);color:var(--text);font-family:-apple-system,"Segoe UI",Malgun Gothic,sans-serif;font-size:14px;}
  .wrap{max-width:1080px;margin:0 auto;padding:20px 16px 60px;}
  h1{font-size:20px;} h2{font-size:15px;color:var(--muted);margin-top:28px;}
  .meta{color:var(--muted);font-size:12.5px;}
  .scroll{overflow-x:auto;}
  table{width:100%;border-collapse:collapse;background:var(--panel);border:1px solid var(--border);border-radius:10px;overflow:hidden;margin-top:10px;}
  thead th{text-align:left;font-size:12px;color:var(--muted);text-transform:uppercase;padding:10px 12px;border-bottom:1px solid var(--border);}
  tbody td{padding:8px 12px;border-bottom:1px solid var(--border);vertical-align:top;}
  tbody tr:last-child td{border-bottom:none;}
  .code{font-family:ui-monospace,Consolas,monospace;font-weight:600;}
  .rate{font-weight:700;}
  .s-VULN{color:var(--vuln);font-weight:600;} .s-MANUAL{color:var(--manual);font-weight:600;}
  .s-ERROR{color:var(--error);font-weight:600;} .s-NA{color:var(--na);} .s-GOOD{color:var(--good);font-weight:600;}
  .human{display:inline-block;margin-left:4px;padding:0 6px;border-radius:999px;font-size:11px;border:1px solid var(--manual);color:var(--manual);}
  .cls-NEW_VULN{color:var(--vuln);} .cls-FIXED{color:var(--good);} .cls-UNFIXED{color:var(--vuln);}
  .cls-CHECK{color:var(--manual);} .cls-UNCHANGED_GOOD{color:var(--muted);}
  .mv-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:10px 0;}
  .mv-bar input,.mv textarea{background:var(--panel);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:6px 8px;font-size:13px;}
  .mv textarea{width:100%;min-height:34px;font-family:inherit;}
  button{background:var(--accent);color:#fff;border:none;border-radius:6px;padding:6px 12px;font-size:13px;cursor:pointer;}
  footer{color:var(--muted);font-size:12px;margin-top:24px;text-align:center;}
"""


def _esc(v) -> str:
    return html.escape(str(v if v is not None else ""))


def _page(title: str, body: str, script: str = "") -> str:
    return ("<!doctype html>\n<html lang=\"ko\">\n<head>\n<meta charset=\"utf-8\">\n"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
            f"<title>{_esc(title)}</title>\n<style>{_CSS}</style>\n</head>\n<body><div class=\"wrap\">\n"
            f"{body}\n<footer>kisa-infra-audit lib/merge.py</footer>\n</div>{script}</body></html>\n")


def _json_script(elem_id: str, obj) -> str:
    # "</" 를 "<\/" 로 - 결과 값에 "</script>" 가 섞여도 블록이 끝나지 않게 한다(report.html 과 같은 처리).
    text = json.dumps(obj, ensure_ascii=False).replace("</", "<\\/")
    return f"<script id=\"{elem_id}\" type=\"application/json\">{text}</script>\n"


def _status_cell(it: dict | None) -> str:
    if it is None:
        return "<td class=\"meta\">(없음)</td>"
    h = it.get("_human")
    if h:
        title = _esc(f"사유: {h['reason']} / 판정자: {h['judged_by'] or '-'} / {h['judged_at'] or '-'}")
        return (f"<td><span class=\"s-{h['verdict']}\">{STATUS_KO[h['verdict']]}</span>"
                f"<span class=\"human\" title=\"{title}\">사람 판정</span><div class=\"meta\">원래 수동점검</div></td>")
    s = it.get("status")
    return f"<td><span class=\"s-{_esc(s)}\">{_esc(STATUS_KO.get(s, s))}</span></td>"


# 병합 보고서의 수동점검 판정 입력(G-05). report.html(lib/report/tail.html)과 같은 manual_verdicts.json 형식을
# 호스트마다 하나씩 내려받는다. 서버 없이 브라우저에서만 동작한다.
_MV_SCRIPT = """
<script>
(function(){
  "use strict";
  var el = document.getElementById("mv-data");
  if (!el) return;
  var hosts = JSON.parse(el.textContent);
  function pad(n){ return (n < 10 ? "0" : "") + n; }
  function isoLocal(d){
    var off = -d.getTimezoneOffset(), sign = off >= 0 ? "+" : "-"; off = Math.abs(off);
    return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())+"T"+pad(d.getHours())+":"+pad(d.getMinutes())+":"+pad(d.getSeconds())
      + sign + pad(Math.floor(off/60)) + ":" + pad(off%60);
  }
  function download(name, obj){
    var blob = new Blob([JSON.stringify(obj, null, 2) + "\\n"], {type: "application/json"});
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click();
    setTimeout(function(){ URL.revokeObjectURL(a.href); a.parentNode.removeChild(a); }, 1000);
  }
  Array.prototype.forEach.call(document.querySelectorAll("button.mv-dl"), function(btn){
    btn.addEventListener("click", function(){
      var hi = parseInt(btn.getAttribute("data-hi"), 10), h = hosts[hi];
      var by = document.getElementById("mv-by").value.trim();
      var now = isoLocal(new Date()), out = [], bad = [];
      h.codes.forEach(function(code, ci){
        var sel = document.querySelector('input[name="mv-'+hi+'-'+ci+'"]:checked');
        var reason = document.getElementById("mv-r-"+hi+"-"+ci).value.trim();
        if (!sel && !reason) return;
        if (!sel || !reason) { bad.push(code); return; }
        out.push({code: code, verdict: sel.value, reason: reason, judged_by: by, judged_at: now});
      });
      if (!by) { alert("판정자를 입력하세요."); return; }
      if (bad.length) { alert("판정(취약/양호)과 사유를 모두 입력하세요: " + bad.join(", ")); return; }
      if (!out.length) { alert(h.host + " 에 입력한 판정이 없습니다."); return; }
      download("manual_verdicts_" + h.host.replace(/[^A-Za-z0-9._-]/g, "_") + ".json",
        {host: h.host, category: h.category, generated_from: h.generated_from, verdicts: out});
    });
  });
})();
</script>
"""


def _manual_input_section(results: list[dict], guide_by_code: dict) -> tuple[str, str]:
    """아직 사람 판정이 없는 MANUAL 항목의 입력 표와 그 데이터 블록. 없으면 빈 문자열."""
    data, blocks = [], []
    for r in sorted(results, key=lambda x: str(x.get("host", ""))):
        pending = [it for it in r.get("items", []) if it.get("status") == "MANUAL" and not it.get("_human")]
        if not pending:
            continue
        hi = len(data)
        pending.sort(key=lambda it: (SEV_ORDER.get(guide_by_code.get(it["code"], {}).get("severity", ""), 9), it["code"]))
        data.append({"host": r.get("host", "unknown"), "category": r.get("category", ""),
                     "generated_from": r.get("generated_at", ""), "codes": [it["code"] for it in pending]})
        rows = []
        for ci, it in enumerate(pending):
            meta = guide_by_code.get(it["code"], {})
            name = f"mv-{hi}-{ci}"
            rows.append(
                f"<tr class=\"mv\"><td class=\"code\">{_esc(it['code'])}</td><td>{_esc(meta.get('severity', ''))}</td>"
                f"<td>{_esc(meta.get('title', it['code']))}<div class=\"meta\">{_esc(it.get('detail', ''))}</div></td>"
                f"<td style=\"white-space:nowrap\"><label><input type=\"radio\" name=\"{name}\" value=\"VULN\"> 취약</label> "
                f"<label><input type=\"radio\" name=\"{name}\" value=\"GOOD\"> 양호</label></td>"
                f"<td><textarea id=\"mv-r-{hi}-{ci}\" placeholder=\"판정 사유\"></textarea></td></tr>"
            )
        blocks.append(
            f"<h2>{_esc(r.get('host', 'unknown'))} - 수동점검 {len(pending)}건</h2>"
            f"<div class=\"mv-bar\"><button class=\"mv-dl\" data-hi=\"{hi}\" type=\"button\">이 호스트 판정 파일 내려받기</button>"
            f"<span class=\"meta\">진단 시각 {_esc(r.get('generated_at', ''))}</span></div>"
            "<div class=\"scroll\"><table><thead><tr><th>코드</th><th>중요도</th><th>항목명 / 자동 판정 근거</th><th>판정</th><th>사유</th></tr></thead>"
            f"<tbody>{''.join(rows)}</tbody></table></div>"
        )
    if not data:
        return "", ""
    body = (
        "<h2>수동점검 항목 사람 판정 입력</h2>"
        "<div class=\"meta\">취약/양호와 사유를 입력하고 호스트별 판정 파일(manual_verdicts_&lt;호스트&gt;.json)을 내려받아 "
        "<code>merge.py --verdicts</code> 로 다시 병합하면 최종 보고서에 \"사람 판정\"으로 반영된다(result.json 은 바뀌지 않음).</div>"
        "<div class=\"mv-bar\"><label>판정자 <input id=\"mv-by\" type=\"text\" placeholder=\"이름\"></label></div>"
        + "".join(blocks)
    )
    return body, _json_script("mv-data", data) + _MV_SCRIPT


def render_html(path: str, category: str, host_rows: list[dict], item_rows: list[dict],
                results: list[dict] | None = None, guide_by_code: dict | None = None) -> None:
    def rate_color(rate):
        if rate is None:
            return "var(--muted)"
        if rate >= 90:
            return "var(--good)"
        if rate >= 70:
            return "var(--manual)"
        return "var(--vuln)"

    results = results or []
    guide_by_code = guide_by_code or {}
    host_html = []
    for h in host_rows:
        rate_s = f"{h['rate']}%" if h["rate"] is not None else "N/A"
        c = h["counts"]
        # host/env 는 대상 호스트가 써 준 result.json 값이라 HTML 이스케이프 후 삽입한다.
        host_html.append(
            f"<tr><td>{_esc(h['host'])}</td><td>{_esc(h['env'])}</td>"
            f"<td class=\"rate\" style=\"color:{rate_color(h['rate'])}\">{rate_s}</td>"
            f"<td>{c['VULN']}</td><td>{c['MANUAL']}</td><td>{c['ERROR']}</td><td>{c['NA']}</td><td>{c['GOOD']}</td>"
            f"<td>{h.get('human', 0)}</td></tr>"
        )
    item_html = []
    for it in item_rows:
        if it["vuln"] == 0:
            continue
        item_html.append(
            f"<tr><td class=\"code\">{_esc(it['code'])}</td><td>{_esc(it['severity'])}</td><td>{_esc(it['title'])}</td>"
            f"<td>{it['vuln']}/{it['applicable']}</td>"
            f"<td class=\"rate\" style=\"color:{rate_color(100 - it['vuln_rate'])}\">{it['vuln_rate']}%</td></tr>"
        )
    hrows = human_rows(results, guide_by_code)
    human_html = "".join(
        f"<tr><td>{_esc(h['host'])}</td><td class=\"code\">{_esc(h['code'])}</td><td>{_esc(h['title'])}</td>"
        f"<td><span class=\"s-{h['verdict']}\">{STATUS_KO[h['verdict']]}</span><span class=\"human\">사람 판정</span></td>"
        f"<td>{_esc(h['reason'])}</td><td>{_esc(h['judged_by'] or '-')}<div class=\"meta\">{_esc(h['judged_at'])}</div></td></tr>"
        for h in hrows
    )
    mv_body, mv_script = _manual_input_section(results, guide_by_code)
    body = (
        f"<h1>다중 호스트 병합 보고서 - {_esc(category)}</h1>"
        f"<div class=\"meta\">호스트 {len(host_rows)}개 / 생성 시각 {datetime.now():%Y-%m-%d %H:%M:%S}"
        + (f" / 사람 판정 {len(hrows)}건 반영(원래 수동점검, result.json 은 그대로)" if hrows else "") + "</div>"
        "<h2>호스트별 준수율 (낮은 순)</h2>"
        "<div class=\"scroll\"><table><thead><tr><th>호스트</th><th>환경</th><th>준수율</th><th>취약</th><th>수동점검</th><th>오류</th>"
        "<th>해당없음</th><th>양호</th><th>사람 판정</th></tr></thead>"
        f"<tbody>{''.join(host_html) or '<tr><td colspan=9>데이터 없음</td></tr>'}</tbody></table></div>"
        "<h2>전사 공통 취약 항목 (취약 호스트 수 많은 순)</h2>"
        "<div class=\"scroll\"><table><thead><tr><th>코드</th><th>중요도</th><th>항목명</th><th>취약 호스트</th><th>취약률</th></tr></thead>"
        f"<tbody>{''.join(item_html) or '<tr><td colspan=5>취약 항목 없음</td></tr>'}</tbody></table></div>"
        + ("<h2>사람 판정 반영 항목 (원래 수동점검)</h2>"
           "<div class=\"scroll\"><table><thead><tr><th>호스트</th><th>코드</th><th>항목명</th><th>판정</th><th>사유</th><th>판정자</th></tr></thead>"
           f"<tbody>{human_html}</tbody></table></div>" if hrows else "")
        + mv_body
    )
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(_page("다중 호스트 병합 보고서", body, mv_script))


# ---- 조치 전·후 비교(G-04) ----------------------------------------------------------------------------------
def _result_key(r: dict) -> tuple:
    return (str(r.get("host", "unknown")).lower(), str(r.get("category", "")), str(r.get("env", "")))


def classify(b: dict | None, a: dict | None) -> tuple[str, str]:
    """(분류, 사유). b/a 는 조치 전·후 항목(없으면 None). 사람 판정이 있으면 그 판정으로 본다."""
    if b is None or a is None:
        return "CHECK", "조치 전 결과에만 있음" if a is None else "조치 후 결과에만 있음"
    sb, sa = eff_status(b), eff_status(a)
    if sa == "VULN" and sb in ("GOOD", "NA"):
        return "NEW_VULN", ""
    if sb == "VULN" and sa == "GOOD":
        return "FIXED", ""
    if sb == "VULN" and sa == "VULN":
        return "UNFIXED", ""
    if sb in ("GOOD", "NA") and sa in ("GOOD", "NA"):
        return "UNCHANGED_GOOD", ""
    if "MANUAL" in (sb, sa) or "ERROR" in (sb, sa):
        return "CHECK", "수동점검/오류 관련"
    # 남는 경우는 취약→해당없음 - 서비스 제거로 해당없음이 됐는지, 감지 실패인지 사람이 확인
    return "CHECK", f"{STATUS_KO.get(sb, sb)}→{STATUS_KO.get(sa, sa)}"


def build_diff(before: list[dict], after: list[dict], guide_by_code: dict) -> list[dict]:
    bmap = {_result_key(r): r for r in before}
    amap = {_result_key(r): r for r in after}
    for k in sorted(set(bmap) - set(amap)):
        warn(f"조치 후 결과에 없는 호스트: {bmap[k].get('host')} ({k[1]}/{k[2]}) - 모든 항목을 확인 필요로 분류")
    for k in sorted(set(amap) - set(bmap)):
        warn(f"조치 전 결과에 없는 호스트: {amap[k].get('host')} ({k[1]}/{k[2]}) - 모든 항목을 확인 필요로 분류")
    rows = []
    for k in sorted(set(bmap) | set(amap)):
        rb, ra = bmap.get(k), amap.get(k)
        bi = {it["code"]: it for it in (rb or {}).get("items", [])}
        ai = {it["code"]: it for it in (ra or {}).get("items", [])}
        host = (ra or rb).get("host", "unknown")
        for code in sorted(set(bi) | set(ai)):
            b, a = bi.get(code), ai.get(code)
            cls, why = classify(b, a)
            meta = guide_by_code.get(code, {})
            rows.append({"cls": cls, "why": why, "host": host, "category": k[1], "env": k[2], "code": code,
                         "severity": meta.get("severity", ""), "title": meta.get("title", code), "before": b, "after": a})
    order = {c: i for i, (c, _) in enumerate(DIFF_CLASSES)}
    rows.sort(key=lambda x: (order[x["cls"]], SEV_ORDER.get(x["severity"], 9), x["host"].lower(), x["code"]))
    return rows


def _human_note(it: dict | None, side: str) -> str:
    h = (it or {}).get("_human")
    return f"{side} 사람 판정: {STATUS_KO[h['verdict']]} - {h['reason']} ({h['judged_by'] or '-'})" if h else ""


def write_diff_csv(path: str, rows: list[dict]) -> None:
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["class", "class_ko", "host", "category", "env", "code", "severity", "title",
                    "before_status", "before_judged", "after_status", "after_judged", "note", "before_detail", "after_detail"])
        for r in rows:
            b, a = r["before"], r["after"]
            notes = [n for n in (r["why"], _human_note(b, "전"), _human_note(a, "후")) if n]
            w.writerow([
                r["cls"], DIFF_KO[r["cls"]], r["host"], r["category"], r["env"], r["code"], r["severity"], r["title"],
                eff_status(b) or "", ("human" if b.get("_human") else "auto") if b else "",
                eff_status(a) or "", ("human" if a.get("_human") else "auto") if a else "",
                " / ".join(notes), (b or {}).get("detail", ""), (a or {}).get("detail", ""),
            ])


def _diff_counts(rows: list[dict]) -> tuple[dict, dict]:
    total = {c: 0 for c, _ in DIFF_CLASSES}
    per_host: dict[str, dict] = {}
    for r in rows:
        total[r["cls"]] += 1
        per_host.setdefault(r["host"], {c: 0 for c, _ in DIFF_CLASSES})[r["cls"]] += 1
    return total, per_host


def write_diff_summary(path: str, category: str, rows: list[dict], before: list[dict], after: list[dict]) -> str:
    total, per_host = _diff_counts(rows)
    lines = [f"=== {category} 조치 전·후 비교 요약 (조치 전 {len(before)}개 / 조치 후 {len(after)}개 결과) ===",
             f"생성 시각: {datetime.now():%Y-%m-%d %H:%M:%S}", "-" * 72,
             "  " + "  ".join(f"{ko}={total[c]}" for c, ko in DIFF_CLASSES), "-" * 72, "[호스트별]"]
    for host in sorted(per_host, key=str.lower):
        c = per_host[host]
        lines.append(f"  {host:<24} " + "  ".join(f"{ko}={c[k]:>3}" for k, ko in DIFF_CLASSES))
    for cls, ko in DIFF_CLASSES[:4]:
        sel = [r for r in rows if r["cls"] == cls]
        if not sel:
            continue
        lines.append("-" * 72)
        lines.append(f"[{ko} {len(sel)}건]")
        for r in sel:
            extra = f"  ({r['why']})" if r["why"] else ""
            lines.append(f"  {r['host']:<20} {r['code']:<8} ({r['severity'] or '-'}) {r['title'][:36]:<36} "
                         f"{status_label(r['before'])} → {status_label(r['after'])}{extra}")
    text = "\n".join(lines) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return text


def render_diff_html(path: str, category: str, rows: list[dict], before: list[dict], after: list[dict]) -> None:
    total, per_host = _diff_counts(rows)
    host_html = "".join(
        f"<tr><td>{_esc(h)}</td>" + "".join(f"<td class=\"cls-{c}\">{per_host[h][c]}</td>" for c, _ in DIFF_CLASSES) + "</tr>"
        for h in sorted(per_host, key=str.lower)
    )
    sections = []
    for cls, ko in DIFF_CLASSES:
        sel = [r for r in rows if r["cls"] == cls]
        trs = "".join(
            f"<tr><td>{_esc(r['host'])}</td><td class=\"code\">{_esc(r['code'])}</td><td>{_esc(r['severity'])}</td>"
            f"<td>{_esc(r['title'])}" + (f"<div class=\"meta\">{_esc(r['why'])}</div>" if r["why"] else "") + "</td>"
            + _status_cell(r["before"]) + _status_cell(r["after"]) + "</tr>"
            for r in sel
        )
        sections.append(
            f"<h2 class=\"cls-{cls}\">{ko} ({len(sel)}건)</h2>"
            + ("<div class=\"scroll\"><table><thead><tr><th>호스트</th><th>코드</th><th>중요도</th><th>항목명</th><th>조치 전</th><th>조치 후</th></tr></thead>"
               f"<tbody>{trs}</tbody></table></div>" if sel else "<div class=\"meta\">해당 없음</div>")
        )
    n_human = sum(1 for r in rows for it in (r["before"], r["after"]) if it and it.get("_human"))
    body = (
        f"<h1>조치 전·후 비교 보고서 - {_esc(category)}</h1>"
        f"<div class=\"meta\">조치 전 결과 {len(before)}개 / 조치 후 결과 {len(after)}개 / 생성 시각 {datetime.now():%Y-%m-%d %H:%M:%S}"
        + (f" / 사람 판정 {n_human}건 반영(원래 수동점검)" if n_human else "") + "</div>"
        "<h2>분류별 건수</h2><div class=\"scroll\"><table><thead><tr><th>호스트</th>"
        + "".join(f"<th>{ko}</th>" for _, ko in DIFF_CLASSES) + "</tr></thead><tbody>"
        + host_html
        + "<tr><td><b>합계</b></td>" + "".join(f"<td class=\"cls-{c}\"><b>{total[c]}</b></td>" for c, _ in DIFF_CLASSES) + "</tr>"
        "</tbody></table></div>"
        + "".join(sections)
    )
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(_page("조치 전·후 비교 보고서", body))


# ---- 진입점 -----------------------------------------------------------------------------------------------
def _category_of(results: list[dict]) -> str:
    categories = {r.get("category", "") for r in results}
    if len(categories) > 1:
        print(f"경고: 서로 다른 카테고리가 섞여 있습니다: {categories} - 그대로 병합을 진행합니다.", file=sys.stderr)
    return next(iter(sorted(categories)), "unknown")


def run_diff(args, before_args: list[str], after_args: list[str]) -> None:
    bpaths = expand_paths(before_args, args.category_num)
    apaths = expand_paths(after_args, args.category_num)
    if not bpaths or not apaths:
        print(f"오류: 조치 {'전' if not bpaths else '후'} result.json 을 찾지 못했습니다.", file=sys.stderr)
        sys.exit(2)
    overlap = set(map(os.path.abspath, bpaths)) & set(map(os.path.abspath, apaths))
    if overlap:
        print(f"오류: 같은 result.json 이 조치 전·후 양쪽에 있습니다: {sorted(overlap)}", file=sys.stderr)
        sys.exit(2)
    before, after = load_results(bpaths), load_results(apaths)
    if not before or not after:
        print("오류: 유효한 result.json 이 없습니다.", file=sys.stderr)
        sys.exit(2)
    if args.verdicts:
        apply_verdicts(before + after, load_verdict_files(args.verdicts))
    category = _category_of(before + after)
    guide_by_code = load_guide(after or before)
    rows = build_diff(before, after, guide_by_code)
    os.makedirs(args.out, exist_ok=True)
    write_diff_csv(os.path.join(args.out, "diff.csv"), rows)
    text = write_diff_summary(os.path.join(args.out, "diff_summary.txt"), category, rows, before, after)
    render_diff_html(os.path.join(args.out, "diff_report.html"), category, rows, before, after)
    print(text)
    print(f"비교 결과: {args.out} (diff.csv, diff_summary.txt, diff_report.html)")


def main() -> None:
    parser = argparse.ArgumentParser(description="다중 호스트 result.json 병합 / 조치 전·후 비교", add_help=True)
    parser.add_argument("paths", nargs="*", help="병합할 result.json·결과 폴더·상위 폴더(glob 가능)")
    parser.add_argument("--dir", dest="dirpath", help="output/ 와 같이 <host>_<cat>_<ts>/result.json 들을 담은 상위 폴더")
    parser.add_argument("-c", "--category", dest="category_num", help="폴더 탐색 시 카테고리 번호로 필터 (예: 01, 08)")
    parser.add_argument("-o", "--out", required=True, help="병합/비교 결과 출력 경로")
    parser.add_argument("--diff", nargs="*", metavar="PATH",
                        help="조치 전·후 비교: '--diff <전> <후>' 또는 '--diff --before ... --after ...'")
    parser.add_argument("--before", nargs="+", default=[], help="--diff 의 조치 전 결과(파일·폴더 여러 개)")
    parser.add_argument("--after", nargs="+", default=[], help="--diff 의 조치 후 결과(파일·폴더 여러 개)")
    parser.add_argument("--verdicts", nargs="+", default=[], metavar="JSON",
                        help="보고서에서 내려받은 manual_verdicts*.json(사람 판정) - 최종·비교 보고서에 반영")
    args = parser.parse_args()

    if args.diff is not None:
        if args.before or args.after:
            if args.diff or args.paths or not (args.before and args.after):
                print("오류: --diff --before <전...> --after <후...> 형식에서는 --before·--after 를 모두 쓰고 다른 경로를 함께 주지 마세요.",
                      file=sys.stderr)
                sys.exit(2)
            run_diff(args, args.before, args.after)
        else:
            pair = list(args.diff) + list(args.paths)
            if len(pair) != 2:
                print("오류: --diff <조치 전> <조치 후> (각각 하나) 또는 --diff --before <...> --after <...> 로 지정하세요.",
                      file=sys.stderr)
                sys.exit(2)
            run_diff(args, [pair[0]], [pair[1]])
        return
    if args.before or args.after:
        print("오류: --before/--after 는 --diff 와 함께 씁니다.", file=sys.stderr)
        sys.exit(2)

    paths = expand_paths(args.paths, args.category_num)
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
    if args.verdicts:
        apply_verdicts(results, load_verdict_files(args.verdicts))

    category = _category_of(results)
    guide_by_code = load_guide(results)

    os.makedirs(args.out, exist_ok=True)
    write_csv(os.path.join(args.out, "merged.csv"), results, guide_by_code)
    host_rows = per_host_stats(results)
    item_rows = per_item_stats(results, guide_by_code)
    summary_text = write_summary(os.path.join(args.out, "merged_summary.txt"), category, host_rows, item_rows,
                                 human_rows(results, guide_by_code))
    render_html(os.path.join(args.out, "merged_report.html"), category, host_rows, item_rows, results, guide_by_code)

    print(summary_text)
    print(f"병합 결과: {args.out} (merged.csv, merged_summary.txt, merged_report.html)")


if __name__ == "__main__":
    main()
