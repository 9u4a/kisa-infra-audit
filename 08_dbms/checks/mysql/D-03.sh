# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [MySQL]
# 판단 기준(가이드 원문): "기관 정책에 맞게" 적용되었는지는 조직마다 기준이 달라 완전 자동
# 판정 불가. validate_password 컴포넌트 활성화 여부 + default_password_lifetime 값을 증적으로
# 제공하여, 최소한 정책 시행 메커니즘 자체가 켜져 있는지는 자동으로 구분한다(partial).
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    vp=$(mysql_query "SHOW VARIABLES LIKE 'validate_password%';")
    rc=$?
    lifetime=$(mysql_query "SHOW VARIABLES LIKE 'default_password_lifetime';")
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE=""
        return
    fi
    CHECK_EVIDENCE="[validate_password]
$vp
[default_password_lifetime]
$lifetime"
    _lifetime_val=$(printf '%s\n' "$lifetime" | awk '{print $2}')
    if [ -z "$vp" ] && { [ -z "$_lifetime_val" ] || [ "$_lifetime_val" = "0" ]; }; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 복잡도 검증(validate_password) 미설치·기간 제한 미설정"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="정책 시행 메커니즘은 활성화됨 - 값이 기관 정책 기준에 맞는지 수동 확인 필요"
    fi
}
