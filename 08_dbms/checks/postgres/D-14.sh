# D-14 (중) 데이터베이스의 주요 설정 파일, 비밀번호 파일 등의 접근 권한 적절성 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 주요 설정 파일의 일반 사용자 수정 권한 제거 / 취약 = 아님
# postgresql.conf, pg_hba.conf 두 파일 모두 640 이하 권한인지 확인한다(가이드 원문 기준).
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    conf=$(postgres_config_path)
    hba=$(postgres_hba_path)
    if [ -z "$conf" ] && [ -z "$hba" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="postgresql.conf/pg_hba.conf 를 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi

    _bad=""
    _evidence=""
    for f in "$conf" "$hba"; do
        [ -z "$f" ] && continue
        check_owner_perm "$f" "postgres root" 640
        _evidence="$_evidence
[$f] $CHECK_STATUS $CHECK_DETAIL
$CHECK_EVIDENCE"
        [ "$CHECK_STATUS" = "VULN" ] && _bad="$_bad $f"
        [ "$CHECK_STATUS" = "ERROR" ] || [ "$CHECK_STATUS" = "NA" ] && _bad="$_bad $f(확인불가)"
    done

    CHECK_EVIDENCE="$_evidence"
    if [ -n "$_bad" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="다음 파일의 권한이 부적절함:$_bad"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="주요 설정 파일(postgresql.conf, pg_hba.conf) 권한이 적절함"
    fi
}
