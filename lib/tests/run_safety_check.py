"""lib/tests/run_safety_check.py <rs 폴더> <라벨> [--sql <쿼리 로그>] [--allow-fs <정규식>] [--expect 코드=상태 ...] [--nr-same]

lib/tests/run_safety.sh(컨테이너)가 남긴 /rs 를 판정한다 - 진단(run.sh) 운영 안전 기준 S1/S2/S5/S6.
--nr-same: 일반 사용자 결과의 "GOOD/NA 0건" 규칙 대신 항목별 상태가 root 와 같은지 본다(원격 DB 진단 등).
--sql 은 DB 서버가 기록한 쿼리 로그(한 줄에 문장 하나)로, 진단이 읽기 전용 문장만 보냈는지 확인한다(S1).
"""
import html
import json
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# ---- 진단이 DB 에 보내도 되는 문장인지(S1) -----------------------------------------------------------------
# 첫 키워드가 읽기 전용(SELECT/SHOW/...)이어도 부작용이 있는 형태를 막는다(독립 리뷰 지적):
#  - 앞 주석: psql 은 주석까지 보낸다 - 예전에는 "/*" 로 시작하면 통과라 "/* x */ DROP ..." 이 통과했다 → 주석을 지우고 판정
#  - SELECT ... INTO 테이블(PG)/INTO OUTFILE·DUMPFILE·@변수(MySQL), FOR UPDATE/SHARE(잠금)
#  - 부작용 함수: pg_reload_conf·set_config·pg_terminate_backend·pg_cancel_backend·pg_rotate_logfile·pg_switch_wal·
#    pg_stat_reset*·pg_create_*·lo_import/lo_export·nextval/setval·dblink*·pg_advisory*lock·sys_exec 등
#  - WITH x AS (DELETE/UPDATE/INSERT/MERGE ...), EXPLAIN ANALYZE <DML>(실제로 실행됨)
#  - SET 은 세션 범위만 - GLOBAL/PERSIST/PERSIST_ONLY/@@global./@@persist. 가 어느 대입에든 있으면 서버 설정 변경
_SQL_FIRST_OK = re.compile(
    r"^(SELECT|SHOW|WITH|EXPLAIN|DESC|DESCRIBE|USE|BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK|SET|VALUES|TABLE)\b", re.I)
_SQL_DML = re.compile(r"\b(INSERT|UPDATE|DELETE|MERGE|REPLACE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE|COPY|CALL|DO|LOCK|VACUUM|ANALYZE)\b", re.I)
_SQL_SIDE_FUNCS = re.compile(
    r"\b(pg_reload_conf|set_config|pg_terminate_backend|pg_cancel_backend|pg_rotate_logfile|pg_switch_wal|pg_switch_xlog"
    r"|pg_stat_reset\w*|pg_create_\w+|pg_drop_replication_slot|pg_promote|pg_wal_replay_\w+|pg_backup_\w+|pg_start_backup|pg_stop_backup"
    r"|pg_file_write|pg_file_unlink|pg_file_rename|lo_import|lo_export|lo_unlink|lo_create|nextval|setval|dblink\w*"
    r"|pg_advisory\w*lock\w*|pg_try_advisory\w*|pg_notify|txid_current|pg_current_xact_id|sys_exec|sys_eval|get_lock|release_lock"
    r"|sleep|benchmark|pg_sleep\w*)\s*\(", re.I)
_SQL_SET_GLOBAL = re.compile(r"(^|,)\s*(GLOBAL|PERSIST|PERSIST_ONLY)\b|@@(GLOBAL|PERSIST|PERSIST_ONLY)\.", re.I)


def _sql_strip(stmt: str) -> str:
    """주석(/* */, -- 줄 주석, MySQL # 줄 주석)과 문자열 리터럴 내용을 지운다(리터럴 속 단어로 오판하지 않게)."""
    s = re.sub(r"'(?:[^'\\]|\\.|'')*'", "''", stmt, flags=re.S)
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"(--|#)[^\n]*", " ", s)
    return s.strip()


def sql_is_readonly(stmt: str) -> bool:
    s = _sql_strip(stmt)
    if not s:
        return True
    s = s.lstrip("( \t\r\n")
    if not _SQL_FIRST_OK.match(s):
        return False
    head = s.split(None, 1)[0].upper()
    if head == "SET":
        if re.match(r"^SET\s+(PASSWORD|ROLE|DEFAULT\s+ROLE|TRANSACTION\s+READ\s+WRITE)\b", s, re.I):
            return False
        return not _SQL_SET_GLOBAL.search(s[3:])
    if _SQL_SIDE_FUNCS.search(s):
        return False
    if re.search(r"\bINTO\b", s, re.I):          # SELECT ... INTO 테이블 / OUTFILE / DUMPFILE / @변수
        return False
    if re.search(r"\bFOR\s+(UPDATE|SHARE|NO\s+KEY\s+UPDATE|KEY\s+SHARE)\b", s, re.I):
        return False
    if head in ("WITH", "EXPLAIN") and _SQL_DML.search(s):
        # CTE 안의 DML, EXPLAIN ANALYZE <DML> 은 실제로 실행된다(EXPLAIN 만 하는 DML 도 굳이 허용하지 않음)
        return False
    return True


class _SqlOk:
    """예전 SQL_OK(정규식) 인터페이스 호환: SQL_OK.match(문장) 이 참이면 읽기 전용."""
    @staticmethod
    def match(stmt):
        return sql_is_readonly(stmt)


SQL_OK = _SqlOk()


def read(path, default=""):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return default


def items(path):
    try:
        return {it["code"]: it["status"] for it in json.loads(read(path))["items"]}
    except (ValueError, KeyError):
        return None


# 일반 사용자 실행 결과가 없어도 되는 경우: 진단이 명시적으로 실행을 거부했을 때뿐(nr.out 의 문구로 확인)
NR_REFUSE = re.compile(r"실행 거부|root 권한이 필요하여 중단|관리자 권한이 필요하여 중단|must be run as root")


def _json_strings(o):
    if isinstance(o, str):
        yield o
    elif isinstance(o, dict):
        for k, v in o.items():
            yield k
            yield from _json_strings(v)
    elif isinstance(o, list):
        for v in o:
            yield from _json_strings(v)


def text_variants(path):
    """비밀값 검색용: 원문 + HTML 엔티티·JSON 이스케이프를 푼 형태(특수문자 비밀값이 이스케이프되어 원문 검색을 피하는 경우 대비)."""
    raw = read(path)
    out = [raw, html.unescape(raw)]
    try:
        out.append("\n".join(_json_strings(json.loads(raw))))
    except ValueError:
        pass
    # report.html 안에 그대로 이어붙인 result.json(\\uXXXX, \\/ 등) - 정규식으로 JSON 문자열 이스케이프를 푼다
    def unjson(t):
        t = re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), t)
        return re.sub(r"\\([\"\\/])", r"\1", t)
    out.append(unjson(raw))
    out.append(html.unescape(unjson(raw)))
    return out


def diff_lines(rs, name):
    return [l for l in read(os.path.join(rs, name)).splitlines() if l[:1] in "<>"]


def main():
    args = sys.argv[1:]
    rs, label = args[0], args[1]
    sql_log = args[args.index("--sql") + 1] if "--sql" in args else None
    allow_fs = re.compile(args[args.index("--allow-fs") + 1]) if "--allow-fs" in args else None
    expects = [args[i + 1] for i, a in enumerate(args) if a == "--expect"]
    nr_same = "--nr-same" in args
    kv = dict(l.split("=", 1) for l in read(os.path.join(rs, "kv")).split() if "=" in l)
    fails, notes = [], []

    if kv.get("ROOT_RC") == "124":
        fails.append(f"S2: 진단이 제한 시간 안에 끝나지 않음({kv.get('ROOT_SECONDS')}초)")
    root = items(os.path.join(rs, "root.json"))
    if root is None:
        fails.append(f"진단 결과(result.json)가 없음 - rc={kv.get('ROOT_RC')}\n{read(os.path.join(rs, 'root.out'))[-1500:]}")

    for e in expects:
        code, want = e.split("=", 1)
        if root is not None and root.get(code) != want:
            fails.append(f"{code}: 기대={want} 실제={root.get(code)}")
    # ---- S1: 진단 전후 상태(root 실행 "", 일반 사용자 실행 "nr_") ----
    for pre, who in (("", "root"), ("nr_", "일반 사용자")):
        if not os.path.exists(os.path.join(rs, pre + "fs.diff")):
            continue
        fs = diff_lines(rs, pre + "fs.diff")
        if allow_fs:
            fs = [l for l in fs if not allow_fs.search(l)]
        if fs:
            fails.append(f"S1({who}): 진단 전후 파일시스템이 다름\n    " + "\n    ".join(fs[:20]))
        etc = diff_lines(rs, pre + "etc.diff")
        if etc:
            fails.append(f"S1({who}): /etc 파일 내용이 바뀜\n    " + "\n    ".join(etc[:20]))
        # 프로세스: "PID|명령행" 양방향(< 사라짐, > 새로 남음). 스냅샷 명령 자체는 run_safety.sh 가 이미 뺐다.
        procs = diff_lines(rs, pre + "proc.diff")
        if procs:
            fails.append(f"S1({who}): 진단 전후 프로세스가 다름(< 사라짐 / > 남음)\n    " + "\n    ".join(procs[:20]))
        tmp = diff_lines(rs, pre + "tmp.diff")
        if tmp:
            fails.append(f"S1({who}): /tmp·/var/tmp·/dev/shm 이 바뀜(< 전 / > 후)\n    " + "\n    ".join(tmp[:20]))
        sysd = diff_lines(rs, pre + "sys.diff")
        if sysd:
            fails.append(f"S1({who}): 커널 파라미터·마운트·방화벽 상태가 바뀜\n    " + "\n    ".join(sysd[:20]))

    # ---- S5: 출력물 권한·비밀값 ----
    for name, who in (("perm.bad", "root"), ("nr_perm.bad", "일반 사용자")):
        perm = read(os.path.join(rs, name)).split()
        if perm:
            fails.append(f"S5({who}): 출력물에 그룹/기타 접근 권한: {perm[:5]}")
    secrets = [s for s in read(os.path.join(rs, "secrets")).splitlines() if s]
    hits = set(l for l in read(os.path.join(rs, "secret.hit")).splitlines() if l.strip())
    outdir = os.path.join(rs, "out")
    for dp, _, fns in os.walk(outdir):
        for fn in fns:
            p = os.path.join(dp, fn)
            variants = text_variants(p)
            for s in secrets:
                if any(s in v for v in variants):
                    hits.add(f"{s} :: {os.path.relpath(p, outdir)}")
    if secrets and not os.path.isdir(outdir):
        fails.append("S5: 출력물 사본(/rs/out)이 없어 비밀값 검사를 할 수 없음")
    if hits:
        fails.append("S5: 비밀값이 출력물에 남음\n    " + "\n    ".join(sorted(hits)))

    # ---- S2(일반 사용자·멈춤 명령) ----
    if kv.get("NR_RC") == "124":
        fails.append(f"S2: 일반 사용자 진단이 제한 시간 안에 끝나지 않음({kv.get('NR_SECONDS')}초)")
    if "HANG_RC" in kv:
        if kv["HANG_RC"] in ("124", "137"):
            fails.append(f"S2: 외부 명령이 멈추면 진단이 끝나지 않음({kv.get('HANG_SECONDS')}초 제한 초과)\n"
                         + read(os.path.join(rs, "hang.out"))[-800:])
        elif items(os.path.join(rs, "hang.json")) is None:
            fails.append(f"S2: 외부 명령이 멈추는 경우 결과가 없음(rc={kv['HANG_RC']})\n" + read(os.path.join(rs, "hang.out"))[-800:])
        else:
            notes.append(f"멈추는 외부 명령 가짜 실행: {kv.get('HANG_SECONDS')}초에 완료")
        if kv.get("HANG_LEFT", "0") != "0":
            fails.append(f"S2: 진단이 끝난 뒤에도 멈춘 외부 명령 {kv['HANG_LEFT']}개가 남음(시간 제한 없이 호출)")

    # ---- S6: 일반 사용자 실행 ----
    nr = items(os.path.join(rs, "nr.json"))
    if root and nr is not None:
        if set(nr) != set(root):
            fails.append(f"S6: 일반 사용자 결과의 항목 집합이 root 와 다름(누락 {sorted(set(root) - set(nr))[:10]}, "
                         f"추가 {sorted(set(nr) - set(root))[:10]})")
        # 비 root 실행은 진입점이 GOOD/NA 를 ERROR 로 일괄 변환한다(nonroot_unverified) - 남아 있으면 거짓 양호.
        # --nr-same(원격 DB 진단처럼 실행 계정과 무관하게 같은 결과여야 하는 경우): 대신 항목별 상태가 root 와 같아야 한다.
        good_na = [] if nr_same else [f"{c}={s}" for c, s in sorted(nr.items()) if s in ("GOOD", "NA")]
        if nr_same:
            diff = [f"{c}(root={root[c]} 일반={nr.get(c)})" for c in sorted(root) if c in nr and nr[c] != root[c]]
            if diff:
                fails.append("S6: 일반 사용자 실행 결과가 root 와 다름(--nr-same): " + ", ".join(diff[:20]))
        if good_na:
            fails.append("S6: 일반 사용자 실행에 GOOD/NA 가 남음(확인 못 한 것을 양호로 판정): " + ", ".join(good_na[:20]))
        false_good = [f"{c}(root={root[c]} 일반={nr.get(c)})" for c in root
                      if root[c] == "VULN" and nr.get(c) in ("GOOD", "NA")]
        if false_good:
            fails.append("S6: 일반 사용자 실행에서 거짓 양호/해당없음: " + ", ".join(false_good))
        vuln_only = [c for c in root if root[c] in ("GOOD", "NA") and nr.get(c) == "VULN"]
        if vuln_only:
            notes.append("일반 사용자에서만 VULN(확인 못 한 것을 취약으로 판정했을 수 있음): " + ", ".join(vuln_only))
        notes.append("일반 사용자 실행: " + ", ".join(f"{s}={list(nr.values()).count(s)}"
                                                for s in ("GOOD", "VULN", "MANUAL", "ERROR", "NA")))
    elif root:
        if NR_REFUSE.search(read(os.path.join(rs, "nr.out"))):
            notes.append(f"일반 사용자 실행 거부(rc={kv.get('NR_RC')}) - 정상")
        else:
            fails.append(f"S6: 일반 사용자 실행 결과가 없음(rc={kv.get('NR_RC')}, 명시적 실행 거부 문구도 없음)\n"
                         + read(os.path.join(rs, "nr.out"))[-800:])

    if sql_log:
        bad = [s for s in read(sql_log).splitlines() if s.strip() and not SQL_OK.match(s)]
        n = len([s for s in read(sql_log).splitlines() if s.strip()])
        if n == 0:
            fails.append("S1: DB 쿼리 로그가 비어 있음(로그 수집 실패 - 검증 불가)")
        elif bad:
            fails.append(f"S1: 읽기 전용이 아닌 SQL {len(bad)}건\n    " + "\n    ".join(b[:200] for b in bad[:20]))
        else:
            notes.append(f"DB 로 보낸 문장 {n}건 모두 읽기 전용")

    print(("FAIL" if fails else "PASS") + f": {label}/run-safety (root {kv.get('ROOT_SECONDS')}초, 일반 {kv.get('NR_SECONDS')}초)")
    for f in fails:
        print("  - " + f)
    for n in notes:
        print("  · " + n)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
