# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-03.sh: 취약 = passwordcheck 모듈이 shared_preload_libraries 에 없음.
# passwordcheck 는 SQL 함수가 없는 순수 C 훅 모듈이라 CREATE EXTENSION 으로 설치할 수 없고
# (Docker 실기 테스트로 확인한 버그 - checks/postgres/D-03.sh 참고) shared_preload_libraries
# GUC 는 postmaster-context(정적) 파라미터라 서버 재시작이 필요하다 - D-07/D-26 과 동일한
# 논리로 confirm 등급에서 재시작까지 수행한다.
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    before=$(psql_query "SHOW shared_preload_libraries;")
    if printf '%s' "$before" | grep -q passwordcheck; then
        FIX_STATUS="NA"; FIX_DETAIL="passwordcheck 가 이미 shared_preload_libraries 에 있음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi

    new_val="passwordcheck"
    [ -n "$before" ] && new_val="${before},passwordcheck"
    fix_db_queue_rollback "postgres" "ALTER SYSTEM SET shared_preload_libraries = '$before';"
    psql_query "ALTER SYSTEM SET shared_preload_libraries = '$new_val';" >/dev/null 2>&1

    restarted=0
    pg_run_as() {
        if [ "$(id -u)" = "0" ]; then
            su postgres -c "$1" >/dev/null 2>&1
        else
            sh -c "$1" >/dev/null 2>&1
        fi
    }
    if command -v systemctl >/dev/null 2>&1; then
        for svc in postgresql postgresql-16 postgresql-15 postgresql-14 postgresql-13 postgresql-12; do
            systemctl restart "$svc" 2>/dev/null && { restarted=1; break; }
        done
    fi
    if [ "$restarted" -eq 0 ] && command -v pg_ctlcluster >/dev/null 2>&1; then
        _cluster_line=$(pg_lsclusters 2>/dev/null | awk 'NR==2{print $1, $2}')
        if [ -n "$_cluster_line" ]; then
            pg_ctlcluster $_cluster_line restart 2>/dev/null && restarted=1
        fi
    fi
    if [ "$restarted" -eq 0 ] && command -v pg_ctl >/dev/null 2>&1 && [ -n "${PGDATA:-}" ]; then
        pg_run_as "pg_ctl restart -D '$PGDATA' -m fast" && restarted=1
    fi

    if [ "$restarted" -eq 1 ]; then
        sleep 2
        after=$(psql_query "SHOW shared_preload_libraries;")
        if printf '%s' "$after" | grep -q passwordcheck; then
            FIX_STATUS="APPLIED"
            FIX_DETAIL="shared_preload_libraries 에 passwordcheck 추가 후 PostgreSQL 재시작하여 적용함"
        else
            FIX_STATUS="ERROR"
            FIX_DETAIL="재시작은 했으나 shared_preload_libraries 에 passwordcheck 가 반영되지 않음(현재값: $after)"
        fi
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="shared_preload_libraries 설정은 변경했으나(재시작 후 반영) PostgreSQL 재시작 방법을 찾지 못함 - 수동 재시작 필요"
    fi
    FIX_EVIDENCE=""
}
