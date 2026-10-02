# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [MySQL] — 조치 [fix: auto]
# checks/mysql/D-11.sh 가 찾아낸 root/mysql.% 외 계정의 mysql 스키마 권한을 회수한다.
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT DISTINCT grantee FROM information_schema.schema_privileges WHERE table_schema='mysql' AND grantee NOT LIKE \"'root'@%\" AND grantee NOT LIKE \"'mysql.%\" ORDER BY grantee;")
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="mysql 스키마에 대한 비인가 권한이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for grantee in $out; do
        IFS=$old_ifs
        [ -z "$grantee" ] && { IFS='
'; continue; }
        # grantee 는 "'user'@'host'" 형식 그대로 반환됨
        fix_db_queue_rollback "mysql" "-- D-11: $grantee 에서 mysql.* 권한 회수함(원본 권한 종류를 알 수 없어 자동 재부여 불가, 필요 시 관리자가 재부여)"
        mysql_query "REVOKE ALL PRIVILEGES ON mysql.* FROM $grantee;" >/dev/null 2>&1
        applied="$applied $grantee"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="mysql 스키마 권한 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="권한 회수 실패"
    fi
    FIX_EVIDENCE=""
}
