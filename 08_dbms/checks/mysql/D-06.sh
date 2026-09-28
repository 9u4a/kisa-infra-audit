# D-06 (중) DB 사용자 계정을 개별적으로 부여하여 사용 [MySQL]
# 판단 기준(가이드 원문): 계정이 "공용"으로 실제 여러 사람에게 공유되는지는 쿼리만으로 확인
# 불가 - 완전 자동 판정 불가. 로그인 가능한 전체 계정 목록을 증적으로 제공한다.
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE account_locked='N' ORDER BY user, host;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="로그인 가능한 계정 목록 - 사용자별로 개별 계정을 쓰고 있는지(공용 계정 여부) 수동 검토 필요"
    CHECK_EVIDENCE="$out"
}
