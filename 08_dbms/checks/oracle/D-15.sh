# D-15 (하) 관리자 이외의 사용자가 오라클 리스너의 접속을 통해 리스너 로그 및 trace 파일에 대한 변경 제한 [Oracle]
# 판단 기준(가이드 원문): 양호 = 설정 파일 권한이 관리자로 제한 & 파라미터 변경 방지 옵션 설정
#                        취약 = 둘 중 하나라도 아님
run_check() {
    f=$(oracle_listener_ora)
    if [ -z "$f" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="listener.ora 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    restrict=$(grep -i 'ADMIN_RESTRICTIONS_' "$f")
    check_owner_perm "$f" "oracle root" 644
    _perm_status=$CHECK_STATUS
    _perm_detail=$CHECK_DETAIL
    CHECK_EVIDENCE="[$f] $_perm_detail
$restrict"
    # "=" 과 값 사이에 공백이 있는 표준 listener.ora 표기(예: "ADMIN_RESTRICTIONS_LISTENER = ON",
    # 이 파일의 DEFAULT_SERVICE_LISTENER 항목과 같은 스타일)도 인식해야 한다 - 공백 없는 "=ON"
    # 만 찾는 패턴이라 정상 포맷으로 설정해도 거짓 VULN이 나는 버그가 있었다(Oracle Docker
    # 실기 테스트로 발견, fixes/oracle/D-15.sh 가 쓰는 출력 형식과 맞춰 수정).
    _restrict_on=0
    printf '%s' "$restrict" | grep -qiE '=[[:space:]]*ON\b' && _restrict_on=1
    if [ "$_perm_status" = "GOOD" ] && [ "$_restrict_on" -eq 1 ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="listener.ora 권한이 적절하고 ADMIN_RESTRICTIONS 옵션도 설정되어 있음"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="listener.ora 권한 부적절 또는 ADMIN_RESTRICTIONS 옵션 미설정(권한:$_perm_status, ADMIN_RESTRICTIONS 설정:$_restrict_on)"
    fi
}
