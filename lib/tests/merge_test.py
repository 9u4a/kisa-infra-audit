#!/usr/bin/env python3
"""lib/tests/merge_test.py — lib/merge.py 회귀 테스트(분석자 PC/CI 전용).

X-05(1.3.4): Windows PowerShell 5.1 의 Out-File -Encoding utf8 은 BOM 을 붙이는데, merge.py 가 utf-8 로 읽어
JSONDecodeError → "건너뜀" 경고만 내고 그 호스트를 병합 결과에서 빠뜨렸다. BOM 있는/없는 result.json 을 섞어
두 호스트가 모두 병합되는지 확인한다.
P-22(1.5.0): 같은 호스트의 이전 결과(generated_at 이 더 이른 것)는 빼고 최근 것만 병합해야 한다 - 예전에는 합산해 부풀었다.
G-04(1.6.0): --diff 조치 전·후 분류(신규 취약·조치 완료·미조치·확인 필요·변화 없음 양호)의 모든 경우, 폴더/파일 여러 개 인자.
G-05(1.6.0): --verdicts 사람 판정 반영(원래 MANUAL 보존)과 무시 경우(호스트/카테고리/generated_from 불일치, MANUAL 아님,
  잘못된 verdict, 사유 없음, 없는 코드, 중복은 judged_at 늦은 것). report.html·병합 보고서의 판정 입력 JS 는 node 가
  있으면 구문 검사 + 최소 DOM 대역으로 실제 실행해 내려받는 manual_verdicts.json 을 merge.py 에 다시 넣어 본다.
"""
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MERGE = os.path.join(ROOT, "lib", "merge.py")
sys.path.insert(0, os.path.join(ROOT, "lib"))


def result(host: str, status: str, at: str = "2026-10-29T00:00:00") -> dict:
    return {"tool_version": "test", "guide_version": "2026", "category": "02_windows", "host": host, "env": "test",
            "generated_at": at, "items": [{"code": "W-01", "status": status, "detail": "d", "evidence": ""}]}


def result_items(host: str, at: str, items: dict, category: str = "02_windows") -> dict:
    return {"tool_version": "test", "guide_version": "2026", "category": category, "host": host, "env": "test",
            "generated_at": at, "items": [{"code": c, "status": s, "detail": f"{c} {s}", "evidence": ""} for c, s in items.items()]}


def save(base: str, folder: str, obj: dict) -> str:
    d = os.path.join(base, folder)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "result.json")
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False)
    return p


def save_json(path: str, obj) -> str:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False)
    return path


def run_merge(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, MERGE, *args], capture_output=True, text=True, encoding="utf-8", errors="replace")


def read_csv(path: str) -> list[dict]:
    if not os.path.isfile(path):
        return []
    with open(path, "rb") as f:
        if not f.read(3) == b"\xef\xbb\xbf":
            raise AssertionError(f"{path}: UTF-8 BOM 없음")
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


# ---- 기존: BOM·중복 호스트·비 UTF-8 ------------------------------------------------------------------------
def test_basic(tmp: str) -> list[str]:
    paths = []
    for host, status, enc in (("win-bom", "VULN", "utf-8-sig"), ("linux-nobom", "GOOD", "utf-8")):
        d = os.path.join(tmp, f"{host}_02_20261029-000000")
        os.makedirs(d)
        p = os.path.join(d, "result.json")
        with open(p, "w", encoding=enc, newline="\n") as f:
            json.dump(result(host, status), f, ensure_ascii=False)
        paths.append(p)
    # 같은 호스트 win-bom 의 이전 진단(GOOD) - 최근 것(VULN)만 남아야 한다
    paths.append(save(tmp, "win-bom_02_20261028-000000", result("win-bom", "GOOD", "2026-10-28T00:00:00")))
    # C1(1.5.0): 증적에 UTF-8 이 아닌 바이트(EUC-KR "가")가 든 결과 - 예전에는 UnicodeDecodeError 로 병합 전체가 중단
    d = os.path.join(tmp, "linux-euckr_01_20261029-000000")
    os.makedirs(d)
    raw = json.dumps(result("linux-euckr", "VULN"), ensure_ascii=False).replace('"evidence": ""', '"evidence": "@@"')
    with open(os.path.join(d, "result.json"), "wb") as f:
        f.write(raw.encode("utf-8").replace(b"@@", bytes([0xB0, 0xA1]) + b" file"))
    paths.append(os.path.join(d, "result.json"))
    out = os.path.join(tmp, "merged")
    proc = run_merge([*paths, "-o", out])
    fails = []
    if proc.returncode != 0:
        fails.append(f"merge.py 종료 코드 {proc.returncode}: {proc.stderr.strip()}")
    if "건너뜀" in proc.stderr:
        fails.append(f"건너뛴 결과 있음: {proc.stderr.strip()}")
    rows = [(row["host"], row["status"]) for row in read_csv(os.path.join(out, "merged.csv"))]
    if sorted(rows) != [("linux-euckr", "VULN"), ("linux-nobom", "GOOD"), ("win-bom", "VULN")]:
        fails.append(f"병합 결과 불일치(같은 호스트는 최근 결과만): {sorted(rows)}")
    return fails


# ---- G-04 조치 전·후 비교 ------------------------------------------------------------------------------------
B_AT, A_AT = "2026-11-01T10:00:00+0900", "2026-11-02T10:00:00+0900"
# 코드: (조치 전, 조치 후, 기대 분류). None = 그쪽 결과에 항목 없음
DIFF_CASES = {
    "W-01": ("GOOD", "VULN", "NEW_VULN"),
    "W-02": ("NA", "VULN", "NEW_VULN"),
    "W-03": ("VULN", "GOOD", "FIXED"),
    "W-04": ("VULN", "VULN", "UNFIXED"),
    "W-05": ("MANUAL", "GOOD", "CHECK"),
    "W-06": ("VULN", "ERROR", "CHECK"),
    "W-07": ("GOOD", "GOOD", "UNCHANGED_GOOD"),
    "W-08": ("NA", "GOOD", "UNCHANGED_GOOD"),
    "W-09": ("VULN", None, "CHECK"),
    "W-10": (None, "GOOD", "CHECK"),
    "W-11": ("VULN", "NA", "CHECK"),
    "W-12": ("MANUAL", "MANUAL", "FIXED"),         # 전 사람 판정 VULN, 후 사람 판정 GOOD
    "W-13": ("MANUAL", "MANUAL", "NEW_VULN"),      # 전 사람 판정 GOOD, 후 사람 판정 VULN
    "W-14": ("MANUAL", "MANUAL", "CHECK"),         # 판정 없음
    "W-15": ("ERROR", "GOOD", "CHECK"),
    "W-16": ("GOOD", "MANUAL", "CHECK"),
}


def test_diff(tmp: str) -> list[str]:
    fails = []
    bdir, adir = os.path.join(tmp, "before"), os.path.join(tmp, "after")
    bi = {c: v[0] for c, v in DIFF_CASES.items() if v[0]}
    ai = {c: v[1] for c, v in DIFF_CASES.items() if v[1]}
    bp = save(bdir, "web01_02_20261101-100000", result_items("web01", B_AT, bi))
    ap = save(adir, "WEB01_02_20261102-100000", result_items("WEB01", A_AT, ai))   # 호스트 이름 대소문자 무시
    # 조치 후 쪽에 같은 호스트의 더 이른 결과 - 최근 것만 써야 한다(이 결과면 W-03 이 미조치가 됨)
    save(adir, "WEB01_02_20261101-230000", result_items("WEB01", "2026-11-01T23:00:00+0900", {**ai, "W-03": "VULN"}))
    # 조치 전에만 있는 호스트 → 모든 항목 확인 필요
    bp2 = save(bdir, "db01_02_20261101-100000", result_items("db01", B_AT, {"W-01": "VULN"}))
    # 사람 판정: 전·후 각각(generated_from 으로 어느 쪽인지 구분)
    vb = save_json(os.path.join(tmp, "v_before.json"), {"host": "web01", "category": "02_windows", "generated_from": B_AT, "verdicts": [
        {"code": "W-12", "verdict": "VULN", "reason": "전: 공유 폴더 everyone 쓰기", "judged_by": "김", "judged_at": "2026-11-01T11:00:00+09:00"},
        {"code": "W-13", "verdict": "GOOD", "reason": "전: 확인함", "judged_by": "김", "judged_at": "2026-11-01T11:00:00+09:00"}]})
    va = save_json(os.path.join(tmp, "v_after.json"), {"host": "WEB01", "category": "02_windows", "generated_from": A_AT, "verdicts": [
        {"code": "W-12", "verdict": "GOOD", "reason": "후: 권한 제거 확인", "judged_by": "이", "judged_at": "2026-11-02T11:00:00+09:00"},
        {"code": "W-13", "verdict": "VULN", "reason": "후: 새 계정 발견", "judged_by": "이", "judged_at": "2026-11-02T11:00:00+09:00"}]})

    # ① --diff <전 폴더> <후 폴더>
    out = os.path.join(tmp, "diff1")
    proc = run_merge(["--diff", bdir, adir, "--verdicts", vb, va, "-o", out])
    if proc.returncode != 0:
        return [f"--diff 폴더: exit {proc.returncode} {proc.stderr.strip()[-400:]}"]
    try:
        rows = read_csv(os.path.join(out, "diff.csv"))
    except AssertionError as e:
        return [str(e)]
    got = {r["code"]: r["class"] for r in rows if r["host"].lower() == "web01"}
    for code, (_, _, want) in DIFF_CASES.items():
        if got.get(code) != want:
            fails.append(f"--diff {code} {DIFF_CASES[code][:2]}: 기대={want} 실제={got.get(code)}")
    db = [r for r in rows if r["host"] == "db01"]
    if not db or db[0]["class"] != "CHECK" or "조치 전 결과에만 있음" not in db[0]["note"]:
        fails.append(f"--diff 조치 전에만 있는 호스트: {db}")
    if "조치 후 결과에 없는 호스트: db01" not in proc.stderr:
        fails.append("--diff 한쪽에만 있는 호스트 경고 없음")
    if "이전 결과를 제외함" not in proc.stderr:
        fails.append("--diff 같은 호스트 이전 결과 제외 경고 없음")
    order = [r["class"] for r in rows]
    rank = {"NEW_VULN": 0, "FIXED": 1, "UNFIXED": 2, "CHECK": 3, "UNCHANGED_GOOD": 4}
    if order != sorted(order, key=rank.get) or order[0] != "NEW_VULN":
        fails.append(f"--diff 정렬(신규 취약이 맨 위): {order}")
    w12 = next((r for r in rows if r["code"] == "W-12"), {})
    if (w12.get("before_status"), w12.get("before_judged"), w12.get("after_status"), w12.get("after_judged")) != ("VULN", "human", "GOOD", "human") \
            or "전 사람 판정" not in w12.get("note", "") or "후 사람 판정" not in w12.get("note", ""):
        fails.append(f"--diff 사람 판정 표시(W-12): {w12}")
    summary = open(os.path.join(out, "diff_summary.txt"), encoding="utf-8").read()
    if "신규 취약=3" not in summary or "조치 완료=2" not in summary or "미조치=1" not in summary:
        fails.append(f"diff_summary.txt 건수: {summary.splitlines()[3] if len(summary.splitlines()) > 3 else summary}")
    page = open(os.path.join(out, "diff_report.html"), encoding="utf-8").read()
    for want in ("신규 취약 (3건)", "사람 판정", "원래 수동점검", "변화 없음 양호"):
        if want not in page:
            fails.append(f"diff_report.html 에 '{want}' 없음")
    # 원본 result.json 은 바뀌지 않는다
    if json.load(open(bp, encoding="utf-8"))["items"] != result_items("web01", B_AT, bi)["items"]:
        fails.append("--diff/--verdicts 가 result.json 을 바꿈")

    # ② --diff --before <파일 여러 개> --after <폴더> (판정 없으면 W-12·W-13 은 확인 필요)
    out = os.path.join(tmp, "diff2")
    proc = run_merge(["--diff", "--before", bp, bp2, "--after", ap, "-o", out])
    rows = read_csv(os.path.join(out, "diff.csv")) if proc.returncode == 0 else []
    got = {(r["host"].lower(), r["code"]): r["class"] for r in rows}
    if proc.returncode != 0 or got.get(("web01", "W-12")) != "CHECK" or got.get(("web01", "W-03")) != "FIXED" \
            or got.get(("db01", "W-01")) != "CHECK":
        fails.append(f"--diff --before/--after: exit {proc.returncode} {proc.stderr.strip()[-300:]}")
    # ③ 인자 오류
    for bad in (["--diff", bdir], ["--diff", "--before", bp], ["--before", bp, "--after", ap], ["--diff", bp, bp]):
        p = run_merge(bad + ["-o", os.path.join(tmp, "bad")])
        if p.returncode != 2:
            fails.append(f"--diff 인자 오류 {bad[:3]}: exit {p.returncode}(기대 2)")
    return fails


# ---- G-05 사람 판정 반영·무시 ---------------------------------------------------------------------------------
def test_verdicts(tmp: str) -> list[str]:
    fails = []
    at = "2026-11-03T09:00:00+0900"
    rp = save(tmp, "app01_02_20261103-090000", result_items("app01", at, {"W-01": "MANUAL", "W-02": "MANUAL", "W-03": "VULN",
                                                                         "W-04": "MANUAL", "W-05": "MANUAL", "W-06": "MANUAL"}))
    original = open(rp, encoding="utf-8").read()

    def vf(name, verdicts, host="app01", category="02_windows", gen=at):
        return save_json(os.path.join(tmp, name), {"host": host, "category": category, "generated_from": gen, "verdicts": verdicts})

    def v(code, verdict="VULN", reason="사유", when="2026-11-03T10:00:00+09:00", by="박"):
        return {"code": code, "verdict": verdict, "reason": reason, "judged_by": by, "judged_at": when}

    files = [
        vf("ok.json", [v("W-01", "VULN", "관리자 공유 사용 중"), v("W-02", "GOOD", "확인 결과 정상", by=""),
                       v("W-03", "GOOD"), v("W-04", "MAYBE"), v("W-05", "GOOD", "  "), v("W-99")]),
        vf("dup_old.json", [v("W-06", "VULN", "옛 판정", "2026-11-03T10:00:00+09:00")]),
        vf("dup_new.json", [v("W-06", "GOOD", "새 판정", "2026-11-03T12:00:00+09:00")]),
        vf("host.json", [v("W-04", "GOOD")], host="other"),
        vf("cat.json", [v("W-04", "GOOD")], category="UNIX"),
        vf("gen.json", [v("W-04", "GOOD")], gen="2026-01-01T00:00:00+0900"),
        os.path.join(tmp, "missing.json"),
    ]
    with open(os.path.join(tmp, "broken.json"), "w", encoding="utf-8") as f:
        f.write("{not json")
    files.append(os.path.join(tmp, "broken.json"))
    out = os.path.join(tmp, "mv")
    proc = run_merge([rp, "--verdicts", *files, "-o", out])
    if proc.returncode != 0:
        return [f"--verdicts: exit {proc.returncode} {proc.stderr.strip()[-400:]}"]
    rows = {r["code"]: r for r in read_csv(os.path.join(out, "merged.csv"))}
    want = {"W-01": ("VULN", "MANUAL", "human"), "W-02": ("GOOD", "MANUAL", "human"), "W-03": ("VULN", "VULN", "auto"),
            "W-04": ("MANUAL", "MANUAL", "auto"), "W-05": ("MANUAL", "MANUAL", "auto"), "W-06": ("GOOD", "MANUAL", "human")}
    for code, exp in want.items():
        r = rows.get(code, {})
        if (r.get("status"), r.get("original_status"), r.get("judged")) != exp:
            fails.append(f"--verdicts {code}: 기대(status, original, judged)={exp} 실제={(r.get('status'), r.get('original_status'), r.get('judged'))}")
    if rows.get("W-06", {}).get("verdict_reason") != "새 판정":
        fails.append("--verdicts 중복 판정은 judged_at 늦은 것: " + str(rows.get("W-06")))
    err = proc.stderr
    for w in ("MANUAL 이 아님", "VULN/GOOD 가 아님", "사유(reason)가 비어 있음", "없는 코드 W-99", "호스트/카테고리(other/02_windows)",
              "호스트/카테고리(app01/UNIX)", "generated_from=2026-01-01", "여러 파일에 있음", "missing.json 를 읽을 수 없어",
              "broken.json 를 읽을 수 없어"):
        if w not in err:
            fails.append(f"--verdicts 경고에 '{w}' 없음")
    if open(rp, encoding="utf-8").read() != original:
        fails.append("--verdicts 가 result.json 을 바꿈")
    summary = open(os.path.join(out, "merged_summary.txt"), encoding="utf-8").read()
    if "사람 판정 반영 3건" not in summary or "준수율=  50%" not in summary:
        fails.append("merged_summary.txt 사람 판정 반영/준수율(W-01 취약·W-02 양호·W-03 취약·W-06 양호 = 50%) 불일치")
    page = open(os.path.join(out, "merged_report.html"), encoding="utf-8").read()
    for w in ("사람 판정 반영 항목", "관리자 공유 사용 중", "수동점검 항목 사람 판정 입력", 'id="mv-data"'):
        if w not in page:
            fails.append(f"merged_report.html 에 '{w}' 없음")
    m = re.search(r'<script id="mv-data" type="application/json">(.*?)</script>', page, re.S)
    data = json.loads(m.group(1)) if m else []
    if not data or data[0]["codes"] != ["W-04", "W-05"] or data[0]["generated_from"] != at:
        fails.append(f"병합 보고서 입력 대상(아직 판정 없는 MANUAL W-04·W-05): {data}")
    return fails


# ---- 보고서 JS (node) ------------------------------------------------------------------------------------
# 최소 DOM 대역: getElementById/querySelector(All)/createElement/Blob/URL/localStorage/alert 만 흉내 낸다.
# spec(JSON): ids{ id: {textContent?, value?} }, checked{ selector: value }, buttons[ {data-hi} ], storage{ key: value }, click: id
_HARNESS = r"""
const fs = require("fs");
const spec = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const code = fs.readFileSync(process.argv[2], "utf8");
const out = {alerts: [], downloads: []};
function el(init){
  const e = Object.assign({style:{}, value:"", textContent:"", innerHTML:"", attrs:{}, listeners:{}}, init || {});
  e.addEventListener = (t, f) => { (e.listeners[t] = e.listeners[t] || []).push(f); };
  e.getAttribute = (k) => e.attrs[k];
  e.querySelectorAll = () => []; e.querySelector = () => null;
  e.appendChild = () => {}; e.removeChild = () => {}; e.focus = () => {};
  e.click = () => { if (e.download) out.downloads.push({name: e.download, blob: e.href}); };
  e.parentNode = {removeChild: () => {}};
  return e;
}
const ids = {};
for (const k of Object.keys(spec.ids || {})) ids[k] = el(spec.ids[k]);
const buttons = (spec.buttons || []).map(b => el({attrs: b}));
const blobs = {};
let nblob = 0;
global.Blob = function(parts){ this.text = parts.join(""); };
global.URL = {createObjectURL: (b) => { const k = "blob:" + (++nblob); blobs[k] = b.text; return k; }, revokeObjectURL: () => {}};
global.setTimeout = () => {};
global.alert = (m) => out.alerts.push(String(m));
global.document = {
  getElementById: (id) => ids[id] || (ids[id] = el()),
  querySelectorAll: (sel) => sel === "button.mv-dl" ? buttons : [],
  querySelector: (sel) => (spec.checked && sel in spec.checked) ? {value: spec.checked[sel]} : null,
  createElement: () => el(),
  body: {appendChild: () => {}},
};
global.window = {localStorage: {getItem: (k) => (spec.storage || {})[k] || null, setItem: () => {}}};
global.console = console;
(0, eval)(code);
const targets = spec.click === "button" ? buttons : [ids[spec.click]];
for (const t of targets) for (const f of (t && t.listeners.click) || []) f();
out.downloads = out.downloads.map(d => ({name: d.name, json: JSON.parse(blobs[d.blob])}));
out.tbody = ids.tbody ? ids.tbody.innerHTML.length : 0;
out.panel = ids["mv-panel"] ? ids["mv-panel"].style.display : "";
process.stdout.write(JSON.stringify(out));
"""


def _scripts(page: str) -> list[str]:
    return [m.group(1) for m in re.finditer(r"<script>(.*?)</script>", page, re.S)]


def _node(node: str, tmp: str, js: str, spec: dict, tag: str) -> dict:
    jp, sp, hp = (os.path.join(tmp, f"{tag}.{x}") for x in ("js", "spec.json", "harness.js"))
    for p, t in ((jp, js), (hp, _HARNESS)):
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(t)
    save_json(sp, spec)
    chk = subprocess.run([node, "--check", jp], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if chk.returncode != 0:
        raise AssertionError(f"{tag}: JS 구문 오류 {chk.stderr.strip()[-400:]}")
    p = subprocess.run([node, hp, jp, sp], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise AssertionError(f"{tag}: JS 실행 오류 {p.stderr.strip()[-600:]}")
    return json.loads(p.stdout)


def test_report_js(tmp: str) -> tuple[list[str], str]:
    import report_common as rc
    node = shutil.which("node")
    fails = []
    at = "2026-11-04T09:00:00+0900"
    rp = save(tmp, "js01_02_20261104-090000", result_items("js01", at, {"W-01": "MANUAL", "W-02": "MANUAL", "W-03": "VULN"}))
    html_path = os.path.join(tmp, "report.html")
    rc.render_report_html(os.path.join(ROOT, "lib"), os.path.join(ROOT, "02_windows", "guide.json"), rp, html_path)
    page = open(html_path, encoding="utf-8").read()
    for w in ('id="mv-panel"', 'id="mv-dl"', "manual_verdicts.json", "mvBox"):
        if w not in page:
            fails.append(f"report.html 에 '{w}' 없음")
    if not node:
        return fails, "node 없음 - report.html·병합 보고서 JS 실행 검사 생략(템플릿 문자열 검사만)"
    guide_txt = open(os.path.join(ROOT, "02_windows", "guide.json"), encoding="utf-8").read()
    res_txt = open(rp, encoding="utf-8").read()
    key = "kisa-mv:js01|02_windows|" + at
    spec = {"ids": {"guide-data": {"textContent": guide_txt}, "result-data": {"textContent": res_txt}, "mv-by": {"value": "최판정"}},
            "storage": {key: json.dumps({"W-01": {"verdict": "GOOD", "reason": "패치 확인"}, "W-02": {"verdict": "", "reason": ""}})},
            "click": "mv-dl"}
    try:
        out = _node(node, tmp, _scripts(page)[-1], spec, "report")
    except AssertionError as e:
        return fails + [str(e)], ""
    if out["panel"] != "flex" or out["tbody"] < 100 or out["alerts"] or len(out["downloads"]) != 1:
        fails.append(f"report.html JS: 판정 패널/표/내려받기 동작 이상 {out}")
        return fails, ""
    dl = out["downloads"][0]
    j = dl["json"]
    if dl["name"] != "manual_verdicts.json" or (j["host"], j["category"], j["generated_from"]) != ("js01", "02_windows", at) \
            or [(v["code"], v["verdict"], v["reason"], v["judged_by"]) for v in j["verdicts"]] != [("W-01", "GOOD", "패치 확인", "최판정")] \
            or not re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$", j["verdicts"][0]["judged_at"]):
        fails.append(f"report.html 내려받은 manual_verdicts.json 형식: {dl}")
    # 판정만 있고 사유 없음 → 경고, 내려받지 않음
    spec["storage"][key] = json.dumps({"W-02": {"verdict": "VULN", "reason": ""}})
    out2 = _node(node, tmp, _scripts(page)[-1], spec, "report2")
    if out2["downloads"] or not any("사유" in a for a in out2["alerts"]):
        fails.append(f"report.html JS: 사유 없는 판정을 막지 않음 {out2}")
    # 내려받은 파일을 merge.py 에 다시 넣으면 사람 판정으로 반영
    vpath = save_json(os.path.join(tmp, "dl.json"), j)
    proc = run_merge([rp, "--verdicts", vpath, "-o", os.path.join(tmp, "js_merged")])
    rows = {r["code"]: r for r in read_csv(os.path.join(tmp, "js_merged", "merged.csv"))} if proc.returncode == 0 else {}
    if rows.get("W-01", {}).get("judged") != "human" or rows.get("W-01", {}).get("status") != "GOOD":
        fails.append(f"report.html 이 내려준 판정 파일이 merge.py 에 반영되지 않음: {proc.stderr[-300:]}")
    # 병합 보고서 입력 JS: W-02 남음 → 판정 입력 후 호스트별 파일
    mpage = open(os.path.join(tmp, "js_merged", "merged_report.html"), encoding="utf-8").read()
    m = re.search(r'<script id="mv-data" type="application/json">(.*?)</script>', mpage, re.S)
    mspec = {"ids": {"mv-data": {"textContent": m.group(1) if m else "[]"}, "mv-by": {"value": "정판정"},
                     "mv-r-0-0": {"value": "로그 검토"}},
             "checked": {'input[name="mv-0-0"]:checked': "VULN"}, "buttons": [{"data-hi": "0"}], "click": "button"}
    try:
        out3 = _node(node, tmp, _scripts(mpage)[-1], mspec, "merged")
    except AssertionError as e:
        return fails + [str(e)], ""
    d = out3["downloads"][0] if out3["downloads"] else {}
    if d.get("name") != "manual_verdicts_js01.json" or d["json"]["generated_from"] != at \
            or [(v["code"], v["verdict"], v["reason"], v["judged_by"]) for v in d["json"]["verdicts"]] != [("W-02", "VULN", "로그 검토", "정판정")]:
        fails.append(f"병합 보고서 JS 내려받기: {out3}")
    return fails, f"node {subprocess.run([node, '--version'], capture_output=True, text=True).stdout.strip()} 로 실행 검사"


def main() -> int:
    fails = []
    note = ""
    with tempfile.TemporaryDirectory() as tmp:
        for name, fn in (("basic", test_basic), ("diff", test_diff), ("verdicts", test_verdicts)):
            d = os.path.join(tmp, name)
            os.makedirs(d)
            fails += fn(d)
        d = os.path.join(tmp, "js")
        os.makedirs(d)
        f, note = test_report_js(d)
        fails += f
    if fails:
        print("FAIL: merge_test\n  - " + "\n  - ".join(fails))
        return 1
    print("PASS: merge_test (BOM 있는 Windows 결과·비 UTF-8 증적 결과 포함 3개 호스트 병합, 같은 호스트 이전 결과 제외)")
    print(f"PASS: merge_test --diff ({len(DIFF_CASES)}개 전·후 조합 분류·사람 판정 반영·한쪽에만 있는 호스트·인자 형식)")
    print("PASS: merge_test --verdicts (반영 3건·무시 9가지 경고·result.json 불변·병합 보고서 입력 대상)")
    print(f"PASS: merge_test 보고서 판정 입력 JS ({note})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
