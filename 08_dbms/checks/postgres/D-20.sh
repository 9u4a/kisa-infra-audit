# D-20 (하) 인가되지 않은 Object Owner의 제한 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = Object Owner가 관리자 계정으로 제한 / 취약 = 일반 사용자도 소유
# PostgreSQL은 애플리케이션 스키마의 테이블을 전용 계정이 소유하는 구성이 일반적이라, 관리자
# 계정 외 소유자가 존재하는 것 자체가 이상 징후라 단정할 수 없다 - 목록을 제공해 수동 검토한다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND tableowner != 'postgres' ORDER BY tableowner;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -z "$out" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="postgres 계정 외 테이블 소유자가 없음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="postgres 외 계정이 소유한 테이블이 있음 - 인가된 애플리케이션/관리자 계정인지 수동 검토 필요"
    fi
}
