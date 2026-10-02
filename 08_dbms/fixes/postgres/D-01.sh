# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-01.sh: 취약 = postgres 계정 비밀번호가 NULL. 무작위 강력 비밀번호로 설정한다
# (원문은 증적/로그에 남기지 않음).
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    newpass=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-20)
    [ -z "$newpass" ] && newpass="Ch$(date +%s)Xz9"
    newpass="${newpass}Aa1!"

    fix_db_queue_rollback "postgres" "-- D-01: postgres 비밀번호를 무작위로 설정함(원복 SQL 없음 - 원본이 비어있었다는 사실만 기록)"
    out=$(psql_query "ALTER USER postgres PASSWORD '$newpass';" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="postgres 비밀번호 설정 실패: $out"; FIX_EVIDENCE=""
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="postgres 계정에 무작위 강력 비밀번호를 설정함(원문은 증적에 남기지 않음)"
    FIX_EVIDENCE=""
}
