# D-25 (상) 주기적 보안 패치 및 벤더 권고 사항 적용 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 보안 패치가 적용된 버전 / 취약 = 아닌 버전
# "안전한 버전"인지는 최신 CVE·벤더 공지와 대조해야 하므로 완전 자동 판정 불가 - 현재 버전
# 정보만 증적으로 제공한다 (U-64/W-62 등 패치 관리 항목과 동일한 원칙).
run_check() {
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(psql_query "SELECT version();")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="PostgreSQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="현재 버전: $out - 최신 보안 패치 적용 여부는 벤더 공지와 대조하여 수동 확인 필요"
    CHECK_EVIDENCE="$out"
}
