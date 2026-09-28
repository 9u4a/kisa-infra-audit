# D-12 (상) 안전한 리스너 비밀번호 설정 및 사용 [Oracle]
# 판단 기준(가이드 원문): 양호 = Listener의 비밀번호가 설정된 경우
#                        취약 = 설정되어 있지 않은 경우
# ※ 가이드 원문 참고: "Oracle 12c release 2 이후 버전은 Listener 비밀번호 설정을 지원하지
# 않으므로 해당사항 없음" - 12.2 이상이면 NA, 그 미만 버전만 listener.ora 의 PASSWORDS_ 설정을 확인한다.
run_check() {
    ver=$(oracle_query "SELECT version FROM v\$instance;")
    if [ -n "$ver" ]; then
        _major=$(printf '%s' "$ver" | grep -oE '^[0-9]+' )
        if [ -n "$_major" ] && [ "$_major" -ge 12 ] 2>/dev/null; then
            CHECK_STATUS="NA"; CHECK_DETAIL="Oracle 12c Release 2 이상은 Listener 비밀번호 설정을 지원하지 않음(가이드 원문 명시) - 버전 $ver"; CHECK_EVIDENCE="version=$ver"
            return
        fi
    fi
    f=$(oracle_listener_ora)
    if [ -z "$f" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="listener.ora 파일을 찾을 수 없음"; CHECK_EVIDENCE="version=$ver"
        return
    fi
    line=$(grep -i 'PASSWORDS_' "$f")
    CHECK_EVIDENCE="version=$ver
[$f]
$line"
    if [ -n "$line" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="listener.ora 에 PASSWORDS_ 설정이 존재함"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="listener.ora 에 Listener 비밀번호(PASSWORDS_) 설정이 없음"
    fi
}
