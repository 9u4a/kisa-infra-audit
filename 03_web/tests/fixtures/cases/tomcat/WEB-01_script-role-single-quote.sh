#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 작은따옴표 속성 + manager-script 역할의 기본 계정명 admin(실무 적용 검증 P-04 - 예전에는 큰따옴표·manager-gui 만 봐 GOOD)
# FIX: GOOD 계정명을 webadmin_<무작위> 로 변경(작은따옴표 요소도 username 속성만 교체)
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
insert_before "$UX" '</tomcat-users>' "  <user username='admin' password='Kisa#Case2026pw' roles='manager-script'/>"
assert grep -q "username='admin'" "$UX"
