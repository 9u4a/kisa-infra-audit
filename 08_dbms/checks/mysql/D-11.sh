# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [MySQL]
# 판단 기준(가이드 원문): 양호 = 시스템 테이블(mysql 스키마)에 DBA만 접근 가능
#                        취약 = DBA 외 일반 사용자 계정이 접근 가능
# 진단 검수 D-R2/D-R7: 예전에는 information_schema.schema_privileges(DB 단위 권한)만 봐서 ①관리자가 아닌 접속
# 계정에는 자기 행만 보여 GOOD ②전역 권한(GRANT SELECT ON *.*)·테이블 단위 권한(mysql.user 등)·와일드카드 DB
# 권한(`%`.*)으로 mysql 스키마를 읽는 계정을 놓쳤다. 권한 테이블(mysql.user/db/tables_priv)을 직접 읽는다 -
# 읽을 권한이 없으면 쿼리가 실패해 ERROR 가 된다.
run_check() {
    if ! command -v mysql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    _excl="user <> 'root' AND user NOT LIKE 'mysql.%'"
    sql="SELECT CONCAT(\"'\", user, \"'@'\", host, \"' (전역 권한)\") FROM mysql.user WHERE $_excl AND (Select_priv='Y' OR Insert_priv='Y' OR Update_priv='Y' OR Delete_priv='Y' OR Drop_priv='Y' OR Alter_priv='Y' OR Create_priv='Y')
UNION SELECT CONCAT(\"'\", user, \"'@'\", host, \"' (DB 권한: \", db, \")\") FROM mysql.db WHERE $_excl AND 'mysql' LIKE db
UNION SELECT CONCAT(\"'\", user, \"'@'\", host, \"' (테이블 권한: mysql.\", table_name, \")\") FROM mysql.tables_priv WHERE $_excl AND db = 'mysql'
ORDER BY 1;"
    out=$(mysql_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="MySQL 연결/쿼리 실패(권한 테이블 조회 권한 필요): $(head -1 "$DB_ERR_FILE" 2>/dev/null)"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -n "$out" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="root 외 계정이 mysql 시스템 스키마에 접근 가능한 권한(전역/DB/테이블)을 보유함"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="mysql 시스템 스키마 권한이 root(관리자) 계정으로 제한되어 있음"
    fi
}
