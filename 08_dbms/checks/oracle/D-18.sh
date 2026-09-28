# D-18 (상) 응용프로그램 또는 DBA 계정의 Role이 Public으로 설정되지 않도록 조정 [Oracle]
# 판단 기준(가이드 원문): 양호 = DBA 계정의 Role이 Public으로 설정되지 않은 경우
#                        취약 = Public으로 설정된 경우
run_check() {
    out=$(oracle_query "SELECT granted_role FROM dba_role_privs WHERE grantee = 'PUBLIC';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="PUBLIC 에게 부여된 Role이 존재함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="PUBLIC 에게 부여된 Role이 없음"
    fi
}
