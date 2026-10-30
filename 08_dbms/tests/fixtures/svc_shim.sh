#!/bin/sh
# 08_dbms/tests/fixtures/svc_shim.sh — 테스트 컨테이너 전용 `service <유닛> status|restart` (db_supervisor.sh 가
# /usr/sbin/service 로 설치). 실제 서버의 init 시스템 대신 감독 루프(db_supervisor.sh)가 서버를 다시 띄우므로,
# restart 는 서버를 정상 종료시키고 다음 세대가 뜰 때까지 기다린 뒤 0 을 돌려준다. 서비스 유닛 이름은 mysqld,
# postgresql 만 "실행 중"으로 응답한다(lib/common.sh db_restart_server 는 실행 중인 유닛 하나만 재기동함).
unit=$1
action=${2:-status}
case "$unit" in
    mysqld) comm=mysqld ;;
    postgresql) comm=postgres ;;
    *) exit 1 ;;
esac
main_pid() {
    if [ "$comm" = "postgres" ]; then
        head -n 1 "${PGDATA:-/var/lib/postgresql/data}/postmaster.pid" 2>/dev/null
    else
        for p in /proc/[0-9]*; do
            [ "$(cat "$p/comm" 2>/dev/null)" = "mysqld" ] && { echo "${p#/proc/}"; return; }
        done
    fi
}
pid=$(main_pid)
case "$action" in
    status) [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null ;;
    restart)
        [ -n "$pid" ] || exit 1
        gen=$(cat /tmp/kisa_sv_gen 2>/dev/null)
        if [ "$comm" = "postgres" ]; then kill -INT "$pid"; else kill -TERM "$pid"; fi
        i=0
        while [ "$i" -lt 120 ]; do
            if [ "$(cat /tmp/kisa_sv_gen 2>/dev/null)" != "$gen" ]; then exit 0; fi
            sleep 1; i=$((i + 1))
        done
        exit 1 ;;
    *) exit 1 ;;
esac
