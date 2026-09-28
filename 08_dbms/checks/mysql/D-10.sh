# D-10 (상) 원격에서 DB 서버로의 접속 제한 [MySQL]
# 판단 기준(가이드 원문): 양호 = 지정된 IP에서만 접근 가능하도록 제한 / 취약 = 제한 없음
# host='%' (모든 호스트 허용) 계정이 하나라도 있으면 취약으로 판단한다.
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE host='%';")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="모든 호스트(%)에서 접속 가능한 계정이 존재함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="모든 계정이 특정 호스트/IP로 접속이 제한되어 있음"
    fi
}
