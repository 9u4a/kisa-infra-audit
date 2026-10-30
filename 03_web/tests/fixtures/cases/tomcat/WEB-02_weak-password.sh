#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: manager-gui 계정 비밀번호가 계정명과 같음(유추 쉬움)
# FIX: MANUAL 운영자가 입력한 새 비밀번호(8자 이상, 평문 저장)로 교체 - 평문 비밀번호의 복잡성은 자동 판정 범위 밖이라 재진단 MANUAL
# FIX_INPUT: y|y|Kisa#Case2026pw|Kisa#Case2026pw
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
insert_before "$UX" '</tomcat-users>' '  <user username="opsadm" password="opsadm" roles="manager-gui"/>'
assert grep -q 'username="opsadm" password="opsadm"' "$UX"
