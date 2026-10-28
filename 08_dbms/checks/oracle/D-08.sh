# D-08 (상) 안전한 암호화 알고리즘 사용 [Oracle]
# 판단 기준(가이드 원문): 양호 = SHA-256 이상 해시 알고리즘 사용 / 취약 = SHA-256 미만
# sqlnet.ora 의 SQLNET.ALLOWED_LOGON_VERSION_SERVER 값이 12 이상이면 SHA-512(12c 이상 알고리즘)
# 강제 적용으로 판단한다(가이드 원문: "Oracle DB 알고리즘: 10G(MD5), 11G(SHA-1), 12C(SHA-512, AES)").
run_check() {
    db_remote_skip "sqlnet.ora" && return
    f=$(oracle_sqlnet_ora)
    if [ -z "$f" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="sqlnet.ora 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    if ! conf=$(oracle_conf_active "$f"); then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="sqlnet.ora 를 읽을 수 없음(권한 부족): $f"; CHECK_EVIDENCE=""
        return
    fi
    # # 주석 줄을 설정으로 인정하던 거짓 GOOD 방지(진단 검수 D-R6) - 주석을 지운 내용에서 찾는다.
    line=$(printf '%s\n' "$conf" | grep -i 'ALLOWED_LOGON_VERSION_SERVER')
    CHECK_EVIDENCE="[$f]
$line"
    ver=$(printf '%s' "$line" | grep -oE '[0-9]+' | head -1)
    if [ -n "$ver" ] && [ "$ver" -ge 12 ] 2>/dev/null; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="SQLNET.ALLOWED_LOGON_VERSION_SERVER=$ver (12 이상, SHA-512 강제)"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="SQLNET.ALLOWED_LOGON_VERSION_SERVER 미설정 또는 12 미만 - 구버전 약한 해시 허용"
    fi
}
