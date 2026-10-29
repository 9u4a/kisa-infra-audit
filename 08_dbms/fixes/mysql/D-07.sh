# D-07 (중) root 권한으로 서비스 구동 제한 [MySQL] — 조치 [fix: confirm]
# checks/mysql/D-07.sh 는 /proc 기반으로 "실행 중인" 프로세스의 uid 를 직접 확인하므로, 설정 파일만 고쳐서는
# 재검증을 통과할 수 없다 - mysqld 재기동이 필요하다(DB 클라이언트 연결만 끊김, OS 세션 영향 없음).
# 운영 안전(1.3.0): 실행 계정을 mysql 로 바꾸면 데이터 디렉터리·소켓·로그 파일 소유자가 맞지 않을 때 기동에
# 실패한다. 재기동 후 실제 접속으로 기동을 확인하고, 뜨지 않으면 my.cnf 를 되돌려 다시 기동한다
# (db_restart_or_revert). 예전의 systemd 밖 mysqld_safe 기동 경로는 없앴다.
run_fix() {
    conf=$(mysql_config_path)
    if [ -z "$conf" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 설정 파일(my.cnf)을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    if ! id mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql OS 계정이 없어 변경하지 않음(실행 계정 전환 불가)"; FIX_EVIDENCE=""
        return
    fi

    fix_backup "$conf"
    if grep -qE '^[[:space:]]*user[[:space:]]*=' "$conf"; then
        fix_sed_inplace "$conf" -E 's/^[[:space:]]*user[[:space:]]*=.*/user = mysql/'
    else
        printf '\n[mysqld]\nuser = mysql\n' >> "$conf"
    fi

    db_restart_or_revert "실행 계정(user=mysql) 변경"
    case "$DB_RESTART_RESULT" in
        ok) FIX_STATUS="APPLIED"; FIX_DETAIL="$conf 에 user=mysql 설정 후 mysqld 를 재기동해 적용함(기동 확인)" ;;
        no_method) FIX_STATUS="ERROR"; FIX_DETAIL="이 호스트에서 mysqld 재기동 방법을 찾지 못함(systemd/service 없음) - 설정은 되돌림" ;;
        reverted) FIX_STATUS="ERROR"; FIX_DETAIL="user=mysql 로 재기동하자 mysqld 가 뜨지 않아(데이터 디렉터리 소유자 등) 설정을 되돌리고 다시 기동함(서비스 복구 확인됨)" ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 mysqld 가 뜨지 않음 - $conf 를 되돌렸으나 기동을 확인하지 못함. 즉시 수동 확인 필요" ;;
    esac
    FIX_EVIDENCE=""
}
