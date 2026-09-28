# D-14 (중) 데이터베이스의 주요 설정 파일, 비밀번호 파일 등의 접근 권한 적절성 [Oracle]
# 판단 기준(가이드 원문): 양호 = 주요 설정 파일의 일반 사용자 수정 권한 제거 / 취약 = 아님
# 가이드 원문 기준 권한: network/admin(755), listener.ora/sqlnet.ora(644), dbs/init.ora(640).
run_check() {
    home=$(oracle_home)
    if [ -z "$home" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="ORACLE_HOME 을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    _bad=""
    _evidence=""
    for spec in "$home/network/admin/listener.ora:644" "$home/network/admin/sqlnet.ora:644"; do
        f=${spec%:*}; maxperm=${spec#*:}
        [ ! -f "$f" ] && continue
        check_owner_perm "$f" "oracle root" "$maxperm"
        _evidence="$_evidence
[$f] $CHECK_STATUS $CHECK_DETAIL"
        [ "$CHECK_STATUS" = "VULN" ] && _bad="$_bad $f"
    done
    CHECK_EVIDENCE="$_evidence"
    if [ -z "$_evidence" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="주요 설정 파일(listener.ora/sqlnet.ora)을 찾을 수 없음"
    elif [ -n "$_bad" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="다음 파일의 권한이 부적절함:$_bad"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="주요 설정 파일 권한이 적절함"
    fi
}
