# D-07 (중) root 권한으로 서비스 구동 제한 [MySQL] — 조치 [fix: confirm]
# 원복: 일부 — my.cnf·데이터 파일 소유자는 되돌리지만, root 구동으로 돌아가려면 mysqld 재기동이 필요함
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

    # 1.4.0(D-C3): root 로 구동되던 mysqld 는 데이터 디렉터리에 root 소유 파일(binlog·binlog.index·ibtmp1·
    # ib_buffer_pool 등)을 만든다. user=mysql 만 바꾸면 mysql 계정이 이 파일을 열지 못해 재기동이 항상 실패하고
    # 원복으로 끝났다(Docker 실기: 실제로 root 로 구동되던 = 취약 상태의 서버에서는 조치가 한 번도 성공할 수 없음).
    # 재기동 전에 데이터 디렉터리 안의 root 소유 파일만 mysql 소유로 바꾸고, 원래 소유자·권한은 원복용으로 남긴다.
    datadir=$(mysql_query "SELECT @@datadir;" 2>/dev/null | tr -d '\r' | head -n 1)
    datadir=${datadir%/}
    if [ -z "$datadir" ] || [ ! -d "$datadir" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="데이터 디렉터리(@@datadir)를 확인하지 못해 변경하지 않음 - user=mysql 로 바꾸면 root 소유 파일 때문에 기동에 실패할 수 있음"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$conf"
    rootfiles=$(find "$datadir" -xdev -user 0 2>/dev/null)
    chowned=0
    old_ifs=$IFS; IFS='
'
    for rf in $rootfiles; do
        IFS=$old_ifs
        fix_backup_owner "$rf"
        chown mysql:mysql "$rf" 2>/dev/null && chowned=$((chowned + 1))
        IFS='
'
    done
    IFS=$old_ifs
    if grep -qE '^[[:space:]]*user[[:space:]]*=' "$conf"; then
        fix_sed_inplace "$conf" -E 's/^[[:space:]]*user[[:space:]]*=.*/user = mysql/'
    else
        printf '\n[mysqld]\nuser = mysql\n' >> "$conf"
    fi

    db_restart_or_revert "실행 계정(user=mysql) 변경"
    case "$DB_RESTART_RESULT" in
        ok) FIX_STATUS="APPLIED"; FIX_DETAIL="$conf 에 user=mysql 설정 후 mysqld 를 재기동해 적용함(기동 확인, $datadir 의 root 소유 파일 ${chowned}개를 mysql 소유로 변경)" ;;
        no_method) FIX_STATUS="ERROR"; FIX_DETAIL="이 호스트에서 mysqld 재기동 방법을 찾지 못함(systemd/service 없음) - 설정은 되돌림" ;;
        reverted) FIX_STATUS="ERROR"; FIX_DETAIL="user=mysql 로 재기동하자 mysqld 가 뜨지 않아(데이터 디렉터리 소유자 등) 설정을 되돌리고 다시 기동함(서비스 복구 확인됨)" ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 mysqld 가 뜨지 않음 - $conf 를 되돌렸으나 기동을 확인하지 못함. 즉시 수동 확인 필요" ;;
    esac
    FIX_EVIDENCE=""
}
