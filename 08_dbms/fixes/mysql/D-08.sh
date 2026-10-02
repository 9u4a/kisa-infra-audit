# D-08 (상) 안전한 암호화 알고리즘 사용 [MySQL] — 조치 [fix: confirm]
# checks/mysql/D-08.sh: 취약 = mysql_native_password(SHA-1)를 쓰는 계정 존재. 해당 계정을
# caching_sha2_password(SHA-256)로 전환한다 - 기존 해시를 재사용할 수 없어 비밀번호를 새로
# 설정해야 한다(무작위 생성, 원문은 증적에 남기지 않음 - WEB-02와 동일한 원칙).
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE plugin IN ('mysql_native_password','mysql_old_password');")
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="SHA-1 기반 플러그인을 쓰는 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    fix_db_queue_rollback "mysql" "-- D-08: 계정을 caching_sha2_password 로 전환하며 비밀번호를 재설정함(원복 SQL 없음 - 원본 비밀번호를 알 수 없어 재현 불가)"

    applied=""
    old_ifs=$IFS; IFS='
'
    for line in $out; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        user=$(printf '%s' "$line" | awk '{print $1}')
        host=$(printf '%s' "$line" | awk '{print $2}')
        newpass=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | cut -c1-20)
        [ -z "$newpass" ] && newpass="Ch$(date +%s%N 2>/dev/null || date +%s)Xz9"
        newpass="${newpass}Aa1!"
        mysql_query "ALTER USER '$user'@'$host' IDENTIFIED WITH caching_sha2_password BY '$newpass';" >/dev/null 2>&1
        applied="$applied $user@$host"
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="SHA-256 이상 알고리즘(caching_sha2_password)으로 전환함:$applied(비밀번호도 함께 재설정, 원문은 증적에 남기지 않음)"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="알고리즘 전환 실패"
    fi
    FIX_EVIDENCE=""
}
