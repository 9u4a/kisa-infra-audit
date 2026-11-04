#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# NA: 기본 server.xml 의 UserDatabase(tomcat-users.xml 인증 저장소)만 있음 - DB 연결 정보가 아님(실무 적용 검증 P-13: 예전 VULN)
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
chmod 666 "$SX"
assert grep -q 'org.apache.catalina.UserDatabase' "$SX"
