# D-06 (중) DB 사용자 계정을 개별적으로 부여하여 사용 [Oracle]
# 판단 기준(가이드 원문): 계정이 "공용"으로 실제 여러 사람에게 공유되는지는 쿼리만으로 확인
# 불가 - 완전 자동 판정 불가. 활성 계정 목록을 증적으로 제공한다.
run_check() {
    out=$(oracle_query "SELECT username FROM dba_users WHERE account_status = 'OPEN' ORDER BY username;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="활성 계정 목록 - 사용자별로 개별 계정을 쓰고 있는지(공용 계정 여부) 수동 검토 필요"
    CHECK_EVIDENCE="$out"
}
