#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 작은따옴표 속성 + admin-gui(host-manager) 역할 계정의 비밀번호가 계정명과 같음(실무 적용 검증 P-04 - 예전 GOOD)
# FIX: MANUAL 운영자가 입력한 새 비밀번호로 교체(작은따옴표 password 속성을 큰따옴표로 다시 씀) - 평문 복잡성은 수동 확인이라 재진단 MANUAL
# FIX_INPUT: y|y|Kisa#Case2026pw|Kisa#Case2026pw
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
insert_before "$UX" '</tomcat-users>' "  <user username='hostadm' password='hostadm' roles='admin-gui'/>"
assert grep -q "username='hostadm'" "$UX"
