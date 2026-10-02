# D-08 (상) 안전한 암호화 알고리즘 사용 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-08.sh: 취약 = password_encryption 이 md5. scram-sha-256 으로 전환한다.
# 전역 GUC 값만 바꾸면 되고(check 도 이 값만 확인) 기존 계정의 비밀번호 재설정은 필요 없다 -
# 새로 비밀번호를 바꾸는 계정부터 scram-sha-256 으로 저장된다.
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    before=$(psql_query "SHOW password_encryption;")
    fix_db_queue_rollback "postgres" "ALTER SYSTEM SET password_encryption = '$before'; SELECT pg_reload_conf();"
    psql_query "ALTER SYSTEM SET password_encryption = 'scram-sha-256';" >/dev/null 2>&1
    psql_query "SELECT pg_reload_conf();" >/dev/null 2>&1
    after=$(psql_query "SHOW password_encryption;")
    if printf '%s' "$after" | grep -q "scram-sha-256"; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="password_encryption 을 scram-sha-256 으로 설정함(변경 전: $before)"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="password_encryption 설정 실패(현재값: $after)"
    fi
    FIX_EVIDENCE="password_encryption = $after"
}
