# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [MySQL] — 조치 [fix: confirm]
# checks/mysql/D-01.sh: 취약 = root 계정 비밀번호가 비어있음. 무작위 강력 비밀번호로 설정한다
# (원문은 증적/로그에 남기지 않음 - WEB-02와 동일한 원칙).
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    hosts=$(mysql_query "SELECT host FROM mysql.user WHERE user='root' AND (authentication_string='' OR authentication_string IS NULL);")
    if [ -z "$hosts" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="비밀번호가 비어있는 root 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    fix_db_queue_rollback "mysql" "-- D-01: root 비밀번호를 무작위로 설정함(원복 SQL 없음 - 원본이 빈 값이었다는 사실만 기록, 관리자가 필요 시 직접 재설정)"

    applied=""
    old_ifs=$IFS; IFS='
'
    for h in $hosts; do
        IFS=$old_ifs
        [ -z "$h" ] && { IFS='
'; continue; }
        newpass=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-20)
        [ -z "$newpass" ] && newpass="Ch$(date +%s%N 2>/dev/null || date +%s)Xz9"
        newpass="${newpass}Aa1!"
        mysql_query "ALTER USER 'root'@'$h' IDENTIFIED BY '$newpass';" >/dev/null 2>&1
        applied="$applied $h"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="root@호스트별 무작위 강력 비밀번호를 설정함(호스트:$applied, 원문은 증적에 남기지 않음)"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="root 비밀번호 설정 실패"
    fi
    FIX_EVIDENCE=""
}
