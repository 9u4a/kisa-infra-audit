# D-22 (하) 데이터베이스의 자원 제한 기능을 TRUE로 설정 [Oracle] — 조치 [fix: auto]
# resource_limit 은 동적 파라미터라 즉시 적용된다(인스턴스 재시작 불필요).
run_fix() {
    before=$(oracle_query "SELECT value FROM v\$parameter WHERE name = 'resource_limit';" | tr -d ' \r')
    [ -z "$before" ] && before="FALSE"

    fix_db_queue_rollback "oracle" "ALTER SYSTEM SET resource_limit = $before;"
    out=$(oracle_query "ALTER SYSTEM SET resource_limit = TRUE;" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ALTER SYSTEM 실패: $out"; FIX_EVIDENCE="$out"
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="RESOURCE_LIMIT 을 TRUE로 설정함(변경 전: $before)"
    FIX_EVIDENCE="$out"
}
