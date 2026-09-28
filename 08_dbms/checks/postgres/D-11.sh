# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 시스템 테이블(pg_catalog)에 DBA만 접근 가능
#                        취약 = DBA 외 일반 사용자 계정이 접근 가능
# PUBLIC 에 대한 catalog SELECT 권한과 PostgreSQL 내장 predefined role(pg_로 시작, 예:
# pg_read_all_stats)은 PostgreSQL 기본 설계상 존재하는 시스템 권한이므로 제외하고, 그 외 특정
# 일반 계정에 대한 명시적 권한 부여만 이상 징후로 본다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT DISTINCT grantee FROM information_schema.role_table_grants WHERE table_schema='pg_catalog' AND grantee NOT IN ('postgres','PUBLIC') AND grantee NOT LIKE 'pg\_%' ORDER BY grantee;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="postgres 외 계정에 pg_catalog(시스템 테이블) 명시적 권한이 부여되어 있음"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="pg_catalog 명시적 권한이 관리자 계정(postgres)으로 제한되어 있음"
    fi
}
