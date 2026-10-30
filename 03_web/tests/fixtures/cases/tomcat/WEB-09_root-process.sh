#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: Tomcat 을 root 로 실제 기동
# FIX: NONE Tomcat 실행 계정 전환은 systemd 유닛 User= 등 서비스 구성 변경이 필요해 자동 조치 범위 밖(ERROR·수동 조치 안내, 설정 무변경)
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
"$TC/bin/catalina.sh" start >/dev/null 2>&1
wait_until 30 sh -c 'grep -q "Server startup in" /usr/local/tomcat/logs/catalina.out 2>/dev/null'
assert test "$(tomcat_uids | sort -u)" = 0
