#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 전용 계정(kisatc)으로 Tomcat 실제 기동
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
useradd -r -M -s /usr/sbin/nologin kisatc
chown -R kisatc "$TC/logs" "$TC/temp" "$TC/work" "$TC/webapps" "$TC/conf"
runuser -u kisatc -- "$TC/bin/catalina.sh" start >/dev/null 2>&1
wait_until 30 sh -c 'grep -q "Server startup in" /usr/local/tomcat/logs/catalina.out 2>/dev/null'
assert test -n "$(tomcat_uids)"
assert_not sh -c '. 03_web/tests/fixtures/cases/case_lib.sh; tomcat_uids | grep -qx 0'
