# D-25 (상) 주기적 보안 패치 및 벤더 권고 사항 적용 [Oracle]
# 판단 기준(가이드 원문): 양호 = 보안 패치가 적용된 버전 / 취약 = 아닌 버전
# "안전한 버전"인지는 최신 CVE·벤더 공지와 대조해야 하므로 완전 자동 판정 불가 - 현재 버전
# 정보만 증적으로 제공한다.
run_check() {
    out=$(oracle_query "SELECT banner FROM v\$version WHERE banner LIKE 'Oracle%';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="현재 버전: $out - 최신 보안 패치 적용 여부는 벤더 공지와 대조하여 수동 확인 필요"
    CHECK_EVIDENCE="$out"
}
