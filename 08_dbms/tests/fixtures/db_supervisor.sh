#!/bin/sh
# 08_dbms/tests/fixtures/db_supervisor.sh <mysql|postgres> [서버 추가 인자...]
# 항목별 케이스 테스트(run_tests.sh case 단계)용 DB 서버 컨테이너의 PID 1. 공식 이미지는 DB 서버 자신이 PID 1 이라
# 재기동하면 컨테이너가 끝난다(08_dbms/CLAUDE.md "Docker 단일 프로세스 컨테이너" 참고). 실제 서버의 systemd 처럼
# 서버가 내려가면 다시 띄우는 감독 루프를 PID 1 로 두고, 재기동 수단으로 service 명령(svc_shim.sh)을 /usr/sbin/service 로 설치한다 -
# 재기동이 필요한 조치(mysql D-07, postgres D-03/D-26)를 lib/common.sh db_restart_server 의 실제 경로(service
# <유닛> status/restart)로 끝까지 시험하기 위함. 테스트 전용이며 진단·조치 코드에는 영향이 없다.
#  - mysql: 처음 한 번은 공식 진입점(docker-entrypoint.sh)으로 초기화·기동하고, 이후에는 root 로 mysqld 를 바로
#    띄운다 - 실행 계정을 /etc/my.cnf 의 user= 로 정하게 해야 D-07(root 구동) 상태를 만들 수 있다(공식 진입점은
#    gosu 로 항상 mysql 계정을 강제함).
#  - postgres: 공식 진입점을 다시 실행한다(데이터 디렉터리가 있으면 초기화를 건너뛰고 postgres 계정으로 기동).
#  /tmp/kisa_sv_stop 이 있으면 루프를 끝낸다.
ENGINE=$1
shift
# lib/common.sh 가 PATH 앞에 /usr/sbin 을 두므로 /usr/sbin/service 자리에 설치한다(원본은 .orig 로 보존).
[ -f /usr/sbin/service ] && [ ! -f /usr/sbin/service.orig ] && mv /usr/sbin/service /usr/sbin/service.orig
cp /infra/08_dbms/tests/fixtures/svc_shim.sh /usr/sbin/service
chmod 755 /usr/sbin/service
n=0
while :; do
    n=$((n + 1))
    echo "$n" > /tmp/kisa_sv_gen
    case "$ENGINE" in
        mysql)
            if [ "$n" -eq 1 ]; then docker-entrypoint.sh mysqld "$@"; else mysqld "$@"; fi ;;
        postgres)
            docker-entrypoint.sh postgres "$@" ;;
        *) echo "unknown engine: $ENGINE" >&2; exit 2 ;;
    esac
    echo "[supervisor] $ENGINE 종료(rc=$?) - 다시 기동" >&2
    [ -f /tmp/kisa_sv_stop ] && exit 0
    sleep 1
done
