# D-09 (중) 일정 횟수의 로그인 실패 시 이에 대한 잠금정책 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 로그인 시도 횟수를 제한하는 값을 설정한 경우
#                        취약 = 설정하지 않은 경우
run_check() {
    out=$(oracle_query "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'FAILED_LOGIN_ATTEMPTS';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="FAILED_LOGIN_ATTEMPTS = $out"
    val=$(printf '%s' "$out" | tr -d ' \r')
    if [ "$val" = "UNLIMITED" ] || [ -z "$val" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="DEFAULT 프로파일에 로그인 실패 횟수 제한이 설정되어 있지 않음(UNLIMITED)"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="DEFAULT 프로파일에 로그인 실패 횟수 제한(FAILED_LOGIN_ATTEMPTS=$val)이 설정되어 있음"
    fi
}
