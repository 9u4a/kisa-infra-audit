# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-03.sh: 취약 = passwordcheck 모듈이 shared_preload_libraries 에 없음.
# passwordcheck 는 SQL 함수가 없는 C 훅 모듈이라 CREATE EXTENSION 으로 설치할 수 없고 shared_preload_libraries
# (정적 파라미터)에 넣어 재기동해야 한다 - confirm 등급에서 재기동까지 수행한다.
# 운영 안전(1.3.0):
#  - 먼저 LOAD 로 모듈을 불러 본다. contrib 패키지가 없어 실패하면 아무것도 바꾸지 않는다 - 예전에는 그대로
#    설정하고 재기동해 PostgreSQL 이 뜨지 않았고, DB 가 내려가 있어 SQL 원복도 불가능했다.
#  - 목록 GUC 는 원소마다 따로 인용한다. 예전의 '기존값,passwordcheck' 는 "a,b" 라는 이름 하나로 저장되어
#    기존 라이브러리(pg_stat_statements 등)가 있던 서버는 다음 기동에 실패할 수 있었다. 원복 SQL 도 같다.
#  - postgresql.auto.conf 를 파일로도 백업해, 기동에 실패하면 파일을 되돌리고 다시 기동한다(db_restart_or_revert).
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    before=$(psql_query "SHOW shared_preload_libraries;" | tr -d ' \r')
    if printf '%s' "$before" | tr ',' '\n' | grep -qx passwordcheck; then
        FIX_STATUS="NA"; FIX_DETAIL="passwordcheck 가 이미 shared_preload_libraries 에 있음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi
    if ! out=$(psql_query "LOAD 'passwordcheck';" 2>&1); then
        FIX_STATUS="ERROR"
        FIX_DETAIL="passwordcheck 모듈을 불러올 수 없어(contrib 패키지 미설치 등) 변경하지 않음 - 그대로 설정하면 재기동 시 PostgreSQL 이 뜨지 않음: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)$out"
        FIX_EVIDENCE=""
        return
    fi

    # 원소별 인용: 'a', 'b'
    list=$(printf '%s' "$before" | tr ',' '\n' | sed -e '/^$/d' -e "s/'/''/g" -e "s/.*/'&'/" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    new_list="${list:+$list, }'passwordcheck'"
    if [ -n "$list" ]; then rb="ALTER SYSTEM SET shared_preload_libraries = $list;"; else rb="ALTER SYSTEM RESET shared_preload_libraries;"; fi

    datadir=$(psql_query "SHOW data_directory;" | tr -d ' \r')
    auto_conf="$datadir/postgresql.auto.conf"
    if [ ! -f "$auto_conf" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="$auto_conf 에 접근할 수 없어(DB 서버 호스트에서 실행하지 않음 등) 기동 실패 시 되돌릴 수 없으므로 변경하지 않음 - DB 서버에서 root/postgres 로 실행할 것"
        FIX_EVIDENCE=""
        return
    fi
    fix_backup "$auto_conf"
    fix_db_queue_rollback "postgres" "$rb"
    if ! psql_query "ALTER SYSTEM SET shared_preload_libraries = $new_list;" >/dev/null; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ALTER SYSTEM 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    fi

    db_restart_or_revert "shared_preload_libraries 변경"
    case "$DB_RESTART_RESULT" in
        ok)
            after=$(psql_query "SHOW shared_preload_libraries;" | tr -d ' \r')
            if printf '%s' "$after" | tr ',' '\n' | grep -qx passwordcheck; then
                FIX_STATUS="APPLIED"; FIX_DETAIL="shared_preload_libraries 에 passwordcheck 를 추가하고 재기동해 적용함(기존: ${before:-없음})"
            else
                FIX_STATUS="ERROR"; FIX_DETAIL="재기동했으나 passwordcheck 가 반영되지 않음(현재: $after)"
            fi ;;
        no_method) FIX_STATUS="ERROR"; FIX_DETAIL="이 호스트에서 PostgreSQL 재기동 방법을 찾지 못함 - 설정은 되돌림(원하면 수동으로 설정·재기동)" ;;
        reverted) FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 PostgreSQL 이 뜨지 않아 설정을 되돌리고 다시 기동함(서비스 복구 확인됨)" ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="재기동 후 PostgreSQL 이 뜨지 않음 - 설정을 되돌렸으나 기동을 확인하지 못함. 즉시 수동 확인 필요($auto_conf, 서비스 로그)" ;;
    esac
    FIX_EVIDENCE=""
}
