# D-02 (상) 데이터베이스의 불필요 계정을 제거하거나, 잠금설정 후 사용 [Oracle]
# 판단 기준(가이드 원문): 불필요 계정 존재 여부는 조직의 운영 정책을 알아야 판단 가능
# - 완전 자동 판정 불가. 전체 계정 목록을 증적으로 제공하고 수동 확인을 안내한다.
run_check() {
    out=$(oracle_query "SELECT username, account_status FROM dba_users ORDER BY username;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="전체 계정 목록을 확인하여 불필요한(퇴직자/테스트/데모) 계정이 있는지 수동 검토 필요"
    CHECK_EVIDENCE="$out"
}
