#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 관리 역할 계정명이 추측하기 쉬운 이름(manager) - 가이드 취약 기준 "추측하기 쉬운 문자 조합"
#       (1.5.0 A23: 예전에는 admin/tomcat 만 봐 GOOD)
# FIX: GOOD 계정명을 webadmin_<무작위> 로 변경
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
tc_ok() {
    mkdir -p /tmp/kisa_cb/logs /tmp/kisa_cb/temp /tmp/kisa_cb/work
    ln -sfn "$TC/conf" /tmp/kisa_cb/conf
    CATALINA_BASE=/tmp/kisa_cb "$TC/bin/catalina.sh" configtest >/tmp/kisa_cb/configtest.log 2>&1
}
insert_before "$UX" '</tomcat-users>' '  <user username="manager" password="Kisa#Case2026pw" roles="manager-gui"/>'
assert grep -q 'username="manager"' "$UX"
