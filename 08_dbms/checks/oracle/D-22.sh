# D-22 (하) 데이터베이스의 자원 제한 기능을 TRUE로 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = RESOURCE_LIMIT 설정이 TRUE / 취약 = FALSE
run_check() {
    out=$(oracle_query "SELECT value FROM v\$parameter WHERE name = 'resource_limit';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="resource_limit = $out"
    if printf '%s' "$out" | grep -qi TRUE; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="RESOURCE_LIMIT 이 TRUE로 설정되어 있음"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="RESOURCE_LIMIT 이 FALSE로 설정되어 있음"
    fi
}
