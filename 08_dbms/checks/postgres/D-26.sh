# D-26 (상) 데이터베이스의 접근, 변경, 삭제 등의 감사 기록이 기관의 감사 기록 정책에 적합하도록 설정 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 감사 로그 저장 정책 수립·적용 / 취약 = 감사 로그 미저장·정책 미적용
# "기관 정책에 적합"한지는 완전 자동 판정 불가 - logging_collector/log_statement 현재 설정을
# 증적으로 제공한다. logging_collector 가 꺼져 있으면(로그 자체를 남기지 않음) 명백한 취약으로 본다.
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    collector=$(psql_query "SHOW logging_collector;")
    rc=$?
    stmt=$(psql_query "SHOW log_statement;")
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE=""
        return
    fi
    CHECK_EVIDENCE="logging_collector = $collector
log_statement = $stmt"
    case "$collector" in
        *off*) CHECK_STATUS="VULN"; CHECK_DETAIL="logging_collector가 꺼져 있어 감사 로그가 저장되지 않음" ;;
        *) CHECK_STATUS="MANUAL"; CHECK_DETAIL="로그 저장은 활성화됨(logging_collector=$collector) - log_statement 범위가 기관 감사 정책에 맞는지 수동 확인 필요" ;;
    esac
}
