# D-09 (중) 일정 횟수의 로그인 실패 시 이에 대한 잠금정책 설정 [Oracle] — 조치 [fix: auto]
run_fix() {
    before=$(oracle_query "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'FAILED_LOGIN_ATTEMPTS';" | tr -d ' \r')
    [ -z "$before" ] && before="DEFAULT"

    fix_db_queue_rollback "oracle" "ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS $before;"
    out=$(oracle_query "ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS 5;" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ALTER PROFILE 실패: $out"; FIX_EVIDENCE="$out"
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="DEFAULT 프로파일에 FAILED_LOGIN_ATTEMPTS=5 설정함(변경 전: $before)"
    FIX_EVIDENCE="$out"
}
