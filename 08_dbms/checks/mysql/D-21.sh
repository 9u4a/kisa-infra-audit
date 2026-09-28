# D-21 (중) 인가되지 않은 GRANT OPTION 사용 제한 [MySQL]
# 판단 기준(가이드 원문): 양호 = WITH GRANT OPTION이 필요한 Role 에만 설정 / 취약 = 아님
# root 외 계정 중 Grant_priv='Y'(전역 GRANT 권한 보유)인 계정이 있으면 취약으로 판단한다.
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE Grant_priv='Y' AND user != 'root';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="root 외 계정에 전역 GRANT 권한(Grant_priv)이 부여되어 있음"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="root 외 계정에 전역 GRANT 권한이 부여되어 있지 않음"
    fi
}
