# D-26 (상) 감사 기록 설정 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-26.sh: 취약 = logging_collector=off. logging_collector 는 postmaster
# context(정적) 파라미터라 ALTER SYSTEM + pg_reload_conf() 만으로는 적용되지 않고 서버 재시작이
# 필요하다 - D-07/D-19 와 동일한 논리로 confirm 등급에서 재시작까지 수행한다(DB 클라이언트
# 연결만 영향, 이 스크립트의 OS 세션에는 영향 없음).
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi

    fix_db_queue_rollback "postgres" "ALTER SYSTEM SET logging_collector = off;"
    psql_query "ALTER SYSTEM SET logging_collector = on;" >/dev/null 2>&1
    psql_query "ALTER SYSTEM SET log_statement = 'mod';" >/dev/null 2>&1

    # 복구 우선순위: systemd 서비스(일반 VM/베어메탈) > Debian 클러스터 래퍼 > pg_ctl 직접 호출.
    # pg_ctl/postgres 는 안전을 위해 root 실행을 거부하므로, root 로 실행 중이면 postgres OS
    # 계정으로 전환(su)해서 호출해야 한다. 주의: 단일 프로세스 컨테이너(postgres 공식 이미지처럼
    # postgres 서버 자체가 PID 1인 경우)에서는 이 재시작이 컨테이너 자체를 종료시킨다 - 실제
    # systemd 환경(VM/베어메탈)에서는 발생하지 않는 Docker 특유의 제약이며, 이 코드 경로는
    # Docker 실기 테스트로 "ALTER SYSTEM 설정까지는 정상 적용됨"만 확인했고 재시작 자체는
    # 코드 리뷰로만 검증했다(08_dbms/CLAUDE.md 참고).
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
        collector=$(psql_query "SHOW logging_collector;")
        if printf '%s' "$collector" | grep -qi on; then
            FIX_STATUS="APPLIED"
            FIX_DETAIL="logging_collector=on 설정 후 PostgreSQL 재시작하여 적용함"
        else
            FIX_STATUS="ERROR"
            FIX_DETAIL="재시작은 수행했으나 logging_collector 가 여전히 off 로 확인됨(collector=$collector)"
        fi
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="ALTER SYSTEM 은 적용했으나(재시작 후 반영) PostgreSQL 재시작 방법을 찾지 못함 - 수동 재시작 필요"
    fi
    FIX_EVIDENCE=""
}
