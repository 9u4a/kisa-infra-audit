#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: DB 연결 리소스(jdbc DataSource)가 있는 server.xml 이 644(다른 사용자가 DB 비밀번호를 읽음)
# FIX: GOOD 해당 파일을 600 으로
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
insert_after "$SX" '<GlobalNamingResources>' '    <Resource name="jdbc/app" auth="Container" type="javax.sql.DataSource" url="jdbc:mysql://db:3306/app" username="app" password="Kisa#Case2026db"/>'
chmod 644 "$SX"
assert grep -q 'jdbc/app' "$SX"
