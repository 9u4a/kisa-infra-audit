#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: error_page 지정 없음(기본 default.conf 의 error_page 주석 처리)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i 's/^\([[:space:]]*\)error_page/\1#error_page/' "$DEF"
assert_not grep -rqE '^[^#]*error_page' /etc/nginx/nginx.conf /etc/nginx/conf.d/
assert nginx -t
