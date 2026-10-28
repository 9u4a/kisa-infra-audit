"""lib/tests/run_safety_check.py <rs 폴더> <라벨> [--sql <쿼리 로그>] [--allow-fs <정규식>] [--expect 코드=상태 ...]

lib/tests/run_safety.sh(컨테이너)가 남긴 /rs 를 판정한다 - 진단(run.sh) 운영 안전 기준 S1/S2/S5/S6.
--sql 은 DB 서버가 기록한 쿼리 로그(한 줄에 문장 하나)로, 진단이 읽기 전용 문장만 보냈는지 확인한다(S1).
"""
import json
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# 진단이 DB 에 보내도 되는 문장(첫 키워드 기준). SET 은 세션 범위만 - GLOBAL/PERSIST 는 서버 설정 변경이다.
SQL_OK = re.compile(
    r"^\s*(\(?\s*SELECT\b|SHOW\b|WITH\b|EXPLAIN\b|DESC(RIBE)?\b|USE\b|BEGIN\b|START\s+TRANSACTION\b|COMMIT\b|ROLLBACK\b"
    r"|SET\s+(?!GLOBAL\b|PERSIST\b|PERSIST_ONLY\b|@@GLOBAL\b|PASSWORD\b|ROLE\b|DEFAULT\s+ROLE\b)\S|/\*|$)",
    re.I,
)


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


def main():
    args = sys.argv[1:]
    rs, label = args[0], args[1]
    sql_log = args[args.index("--sql") + 1] if "--sql" in args else None
    allow_fs = re.compile(args[args.index("--allow-fs") + 1]) if "--allow-fs" in args else None
    expects = [args[i + 1] for i, a in enumerate(args) if a == "--expect"]
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
    fs = [l for l in read(os.path.join(rs, "fs.diff")).splitlines() if l[:1] in "<>"]
    if allow_fs:
        fs = [l for l in fs if not allow_fs.search(l)]
    if fs:
        fails.append("S1: 진단 전후 파일시스템이 다름\n    " + "\n    ".join(fs[:20]))
    etc = [l for l in read(os.path.join(rs, "etc.diff")).splitlines() if l[:1] in "<>"]
    if etc:
        fails.append("S1: /etc 파일 내용이 바뀜\n    " + "\n    ".join(etc[:20]))
    procs = read(os.path.join(rs, "proc.diff")).split()
    procs = [p for p in procs if p not in (">", "sort", "cat", "sh", "diff", "find", "grep", "ls", "date")]
    if procs:
        fails.append(f"S1: 진단 뒤 새 프로세스가 남음: {procs}")
    tmp = read(os.path.join(rs, "tmp.diff")).split()
    tmp = [t for t in tmp if t != ">"]
    if tmp:
        fails.append(f"S1: /tmp·/var/tmp 에 진단이 남긴 파일: {tmp}")
    perm = read(os.path.join(rs, "perm.bad")).split()
    if perm:
        fails.append(f"S5: 출력물에 그룹/기타 접근 권한: {perm[:5]}")
    hits = read(os.path.join(rs, "secret.hit")).strip()
    if hits:
        fails.append("S5: 비밀값이 출력물에 남음\n    " + hits.replace("\n", "\n    "))

    nr = items(os.path.join(rs, "nr.json"))
    if root and nr is not None:
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
        notes.append(f"일반 사용자 실행 결과 없음(rc={kv.get('NR_RC')}) - 실행 거부라면 정상")

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
