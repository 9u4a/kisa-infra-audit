# D-19 (상) OS_ROLES, REMOTE_OS_AUTHENTICATION, REMOTE_OS_ROLES를 FALSE로 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 셋 다 FALSE / 취약 = 하나라도 TRUE
run_check() {
    out=$(oracle_query "SELECT name, value FROM v\$parameter WHERE name IN ('os_roles','remote_os_authent','remote_os_roles') ORDER BY name;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if printf '%s\n' "$out" | grep -qi 'TRUE'; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="os_roles/remote_os_authent/remote_os_roles 중 TRUE로 설정된 값이 있음"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="os_roles/remote_os_authent/remote_os_roles 모두 FALSE로 설정됨"
    fi
}
