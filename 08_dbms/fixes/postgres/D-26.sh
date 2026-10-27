# D-26 (상) 감사 기록 설정 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-26.sh: 취약 = logging_collector=off. logging_collector 는 정적 파라미터라 재기동이 필요하다
# - confirm 등급에서 재기동까지 수행한다(DB 클라이언트 연결만 영향, 이 스크립트의 OS 세션에는 영향 없음).
# 운영 안전(1.3.0): postgresql.auto.conf 를 파일로도 백업하고, 재기동 후 기동을 확인해 뜨지 않으면 되돌리고
# 다시 기동한다(db_restart_or_revert). 예전에는 log_statement 변경을 원복하지 않았다 - 원래 값으로 되돌린다.
# 주의: 단일 프로세스 컨테이너(postgres 가 PID 1)에서는 재기동이 컨테이너를 종료시킨다(Docker 특유 제약).
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    datadir=$(psql_query "SHOW data_directory;" | tr -d ' \r')
    auto_conf="$datadir/postgresql.auto.conf"
    if [ ! -f "$auto_conf" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="$auto_conf 에 접근할 수 없어(DB 서버 호스트에서 실행하지 않음 등) 기동 실패 시 되돌릴 수 없으므로 변경하지 않음"
        FIX_EVIDENCE=""
        return
    fi
    old_stmt=$(psql_query "SHOW log_statement;" | tr -d ' \r')
    fix_backup "$auto_conf"
    fix_db_queue_rollback "postgres" "ALTER SYSTEM SET logging_collector = off;"
    fix_db_queue_rollback "postgres" "ALTER SYSTEM SET log_statement = '${old_stmt:-none}';"
    if ! psql_query "ALTER SYSTEM SET logging_collector = on;" >/dev/null || \
       ! psql_query "ALTER SYSTEM SET log_statement = 'mod';" >/dev/null; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ALTER SYSTEM 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    fi

    db_restart_or_revert "logging_collector 변경"
    case "$DB_RESTART_RESULT" in
        ok)
            collector=$(psql_query "SHOW logging_collector;" | tr -d ' \r')
            if [ "$collector" = "on" ]; then
                FIX_STATUS="APPLIED"; FIX_DETAIL="logging_collector=on, log_statement=mod(기존 ${old_stmt:-none}) 설정 후 재기동해 적용함"
            else
                FIX_STATUS="ERROR"; FIX_DETAIL="재기동했으나 logging_collector 가 on 이 아님(현재: $collector)"
            fi ;;
        no_method) FIX_STATUS="ERROR"; FIX_DETAIL="이 호스트에서 PostgreSQL 재기동 방법을 찾지 못함 - 설정은 되돌림" ;;
        reverted) FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 PostgreSQL 이 뜨지 않아(로그 디렉터리 권한 등) 설정을 되돌리고 다시 기동함(서비스 복구 확인됨)" ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 PostgreSQL 이 뜨지 않음 - 설정을 되돌렸으나 기동을 확인하지 못함. 즉시 수동 확인 필요($auto_conf, 서비스 로그)" ;;
    esac
    FIX_EVIDENCE=""
}
