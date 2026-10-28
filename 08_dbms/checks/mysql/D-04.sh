# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [MySQL]
# 판단 기준(가이드 원문): "필요한 계정에만" 부여되었는지는 조직의 업무 요구를 알아야 판단
# 가능 - 완전 자동 판정 불가. SUPER 권한(관리자 권한) 보유 계정 목록을 증적으로 제공한다.
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    # information_schema.USER_PRIVILEGES 는 관리자가 아니면 자기 행만 보여 목록이 비어 보였다(진단 검수 D-R2) -
    # mysql.user 를 직접 읽어 권한이 없으면 조회 실패(ERROR)가 되게 한다.
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE Super_priv='Y' OR Grant_priv='Y' OR Create_user_priv='Y' ORDER BY user, host;")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="SUPER/GRANT/CREATE USER 권한 보유 계정 목록 - 관리 업무에 실제로 필요한 계정인지 수동 검토 필요"
    CHECK_EVIDENCE="$out"
}
