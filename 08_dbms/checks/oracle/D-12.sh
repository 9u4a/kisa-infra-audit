# D-12 (상) 안전한 리스너 비밀번호 설정 및 사용 [Oracle]
# 판단 기준(가이드 원문): 양호 = Listener의 비밀번호가 설정된 경우
#                        취약 = 설정되어 있지 않은 경우
# ※ 가이드 원문 참고: "Oracle 12c release 2 이후 버전은 Listener 비밀번호 설정을 지원하지
# 않으므로 해당사항 없음" - 12.2 이상이면 NA, 그 미만 버전만 listener.ora 의 PASSWORDS_ 설정을 확인한다.
run_check() {
    ver=$(oracle_query "SELECT version FROM v\$instance;")
    _vrc=$?
    [ $_vrc -ne 0 ] && ver=""
    ver=$(printf '%s' "$ver" | tr -d ' \t\r' | awk 'NF' | head -n 1)
    if [ -n "$ver" ]; then
        _major=$(printf '%s' "$ver" | awk -F. '{print $1+0}')
        _minor=$(printf '%s' "$ver" | awk -F. '{print $2+0}')
        # 12c Release 1(12.1)은 아직 리스너 비밀번호를 지원한다 - 예전에는 12 이상이면 NA 라 12.1 을 놓쳤다(진단 검수 D-R11).
        if [ "$_major" -gt 12 ] || { [ "$_major" -eq 12 ] && [ "$_minor" -ge 2 ]; }; then
            CHECK_STATUS="NA"; CHECK_DETAIL="Oracle 12c Release 2 이상은 Listener 비밀번호 설정을 지원하지 않음(가이드 원문 명시) - 버전 $ver"; CHECK_EVIDENCE="version=$ver"
            return
        fi
    fi
    db_remote_skip "listener.ora(버전 ${ver:-미확인})" && return
    f=$(oracle_listener_ora)
    if [ -z "$f" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="listener.ora 파일을 찾을 수 없음"; CHECK_EVIDENCE="version=$ver"
        return
    fi
    if ! conf=$(oracle_conf_active "$f"); then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="listener.ora 를 읽을 수 없음(권한 부족): $f"; CHECK_EVIDENCE=""
        return
    fi
    # # 주석 줄을 설정으로 인정하던 거짓 GOOD 방지(진단 검수 D-R6) - 주석을 지운 내용에서 찾는다.
    line=$(printf '%s\n' "$conf" | grep -i 'PASSWORDS_')
    CHECK_EVIDENCE="version=$ver
[$f]
$line"
    if [ -n "$line" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="listener.ora 에 PASSWORDS_ 설정이 존재함"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="listener.ora 에 Listener 비밀번호(PASSWORDS_) 설정이 없음"
    fi
}
