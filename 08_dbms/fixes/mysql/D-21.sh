# D-21 (중) 인가되지 않은 GRANT OPTION 사용 제한 [MySQL] — 조치 [fix: auto]
# checks/mysql/D-21.sh 가 찾아낸 root 외 Grant_priv='Y' 계정에서 GRANT OPTION 만 회수한다
# (전체 권한을 회수하는 것이 아니라 "다른 계정에게 권한을 나눠줄 수 있는" 권한만 제거).
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE Grant_priv='Y' AND user != 'root';")
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="root 외 GRANT 권한 보유 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    applied=""
    old_ifs=$IFS; IFS='
'
    for line in $out; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        user=$(printf '%s' "$line" | awk '{print $1}')
        host=$(printf '%s' "$line" | awk '{print $2}')
        fix_db_queue_rollback "mysql" "GRANT GRANT OPTION ON *.* TO '$user'@'$host';"
        mysql_query "REVOKE GRANT OPTION ON *.* FROM '$user'@'$host';" >/dev/null 2>&1
        applied="$applied $user@$host"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="GRANT OPTION 회수:$applied"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="GRANT OPTION 회수 실패"
    fi
    FIX_EVIDENCE=""
}
