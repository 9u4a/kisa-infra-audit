# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [Oracle]
# 판단 기준(가이드 원문): "기관 정책에 맞게" 적용되었는지는 완전 자동 판정 불가. DEFAULT
# 프로파일의 PASSWORD_LIFE_TIME/PASSWORD_VERIFY_FUNCTION 값을 증적으로 제공한다. 둘 다
# UNLIMITED/NULL(정책 미시행)이면 명백한 취약으로 판단한다.
run_check() {
    out=$(oracle_query "SELECT resource_name, limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name IN ('PASSWORD_LIFE_TIME','PASSWORD_VERIFY_FUNCTION','FAILED_LOGIN_ATTEMPTS') ORDER BY resource_name;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    lifetime=$(printf '%s\n' "$out" | grep -i PASSWORD_LIFE_TIME | awk -F'|' '{print $2}' | tr -d ' ')
    verify=$(printf '%s\n' "$out" | grep -i PASSWORD_VERIFY_FUNCTION | awk -F'|' '{print $2}' | tr -d ' ')
    if { [ -z "$lifetime" ] || [ "$lifetime" = "UNLIMITED" ]; } && { [ -z "$verify" ] || [ "$verify" = "NULL" ]; }; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="DEFAULT 프로파일에 비밀번호 사용기간·복잡도 검증 정책이 전혀 설정되어 있지 않음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="정책 시행 메커니즘은 일부 설정됨 - 구체적 값이 기관 기준에 맞는지 수동 확인 필요"
    fi
}
