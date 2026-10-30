#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: <Resource>(UserDatabase)가 있는 server.xml 권한 600
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
chmod 600 "$SX"
assert test "$(stat -c %a "$SX")" = 600
assert_not grep -qE '<Resource([[:space:]/>]|$)' "$CX"
