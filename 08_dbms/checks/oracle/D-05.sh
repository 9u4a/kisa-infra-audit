# D-05 (중) 비밀번호 재사용에 대한 제약 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 비밀번호 재사용 제한 설정을 적용한 경우
#                        취약 = 적용하지 않은 경우
# DEFAULT 프로파일의 PASSWORD_REUSE_TIME/PASSWORD_REUSE_MAX 가 둘 다 UNLIMITED/NULL 이면 취약.
run_check() {
    out=$(oracle_query "SELECT resource_name, limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name IN ('PASSWORD_REUSE_TIME','PASSWORD_REUSE_MAX') ORDER BY resource_name;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    unrestricted=$(printf '%s\n' "$out" | awk -F'|' '{gsub(/ /,"",$2); if ($2!="UNLIMITED" && $2!="NULL" && $2!="") ok=1} END{print ok+0}')
    if [ "$unrestricted" = "1" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="비밀번호 재사용 제한(PASSWORD_REUSE_TIME/MAX) 설정이 적용되어 있음"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 재사용 제한 설정이 적용되어 있지 않음(UNLIMITED/NULL)"
    fi
}
