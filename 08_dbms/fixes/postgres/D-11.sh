# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [PostgreSQL] — 조치 [fix: auto]
# checks/postgres/D-11.sh 가 찾아낸 pg_catalog 명시적 권한을 회수한다.
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT DISTINCT grantee FROM information_schema.role_table_grants WHERE table_schema='pg_catalog' AND grantee NOT IN ('postgres','PUBLIC') AND grantee NOT LIKE 'pg\_%' ORDER BY grantee;")
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="pg_catalog 비인가 권한이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for grantee in $out; do
        IFS=$old_ifs
        [ -z "$grantee" ] && { IFS='
'; continue; }
        fix_db_queue_rollback "postgres" "-- D-11: \"$grantee\" 에서 pg_catalog 권한 회수함(원본 권한 종류를 알 수 없어 자동 재부여 불가)"
        psql_query "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA pg_catalog FROM \"$grantee\";" >/dev/null 2>&1
        applied="$applied $grantee"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="pg_catalog 권한 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="권한 회수 실패"
    fi
    FIX_EVIDENCE=""
}
