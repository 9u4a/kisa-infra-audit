# D-07 (중) root 권한으로 서비스 구동 제한 [MySQL] — 조치 [fix: confirm]
# checks/mysql/D-07.sh 는 /proc 기반으로 "실행 중인" 프로세스의 uid 를 직접 확인하므로, 설정
# 파일만 고쳐서는 재검증을 통과할 수 없다 - mysqld 재시작이 필요하다. 이 재시작은 DB 클라이언트
# 연결만 끊을 뿐 이 스크립트가 실행 중인 OS 세션에는 영향이 없어(Windows/PC의 RDP/WinRM 재시작
# 금지 원칙과는 다른 성격) confirm 등급에서 사람이 동의하면 수행한다.
run_fix() {
    conf=$(mysql_config_path)
    if [ -z "$conf" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 설정 파일(my.cnf)을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$conf"
    if grep -qE '^[[:space:]]*user[[:space:]]*=' "$conf"; then
        sed -i -E 's/^[[:space:]]*user[[:space:]]*=.*/user = mysql/' "$conf"
    else
        printf '\n[mysqld]\nuser = mysql\n' >> "$conf"
    fi

    restarted=0
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart mysqld 2>/dev/null && restarted=1
        [ "$restarted" -eq 0 ] && systemctl restart mysql 2>/dev/null && restarted=1
    fi
    if [ "$restarted" -eq 0 ] && command -v mysqladmin >/dev/null 2>&1 && command -v mysqld_safe >/dev/null 2>&1; then
        mysqladmin shutdown 2>/dev/null
        (mysqld_safe --user=mysql >/dev/null 2>&1 &)
        sleep 2
        restarted=1
    fi

    if [ "$restarted" -eq 1 ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="$conf 에 user=mysql 설정 후 mysqld 재시작함"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="$conf 는 수정했으나 mysqld 재시작 방법을 찾지 못함(systemd 없는 환경) - 수동 재시작 필요"
    fi
    FIX_EVIDENCE=""
}
