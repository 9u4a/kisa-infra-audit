# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [MySQL]
# 판단 기준(가이드 원문): 양호 = 시스템 테이블(mysql 스키마)에 DBA만 접근 가능
#                        취약 = DBA 외 일반 사용자 계정이 접근 가능
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT DISTINCT grantee FROM information_schema.schema_privileges WHERE table_schema='mysql' AND grantee NOT LIKE \"'root'@%\" AND grantee NOT LIKE \"'mysql.%\" ORDER BY grantee;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="root 외 계정이 mysql 시스템 스키마에 대한 권한을 보유함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="mysql 시스템 스키마 권한이 root(관리자) 계정으로 제한되어 있음"
    fi
}
