#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 기본 default.conf 의 server 블록(error_page 50x 가 있는 블록)에 error_page 404 도 지정(실무 적용 검증 P-05)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
insert_after "$DEF" 'error_page   500 502 503 504' '    error_page   404 /404.html;'
assert grep -qE '^[[:space:]]*error_page[[:space:]]+404' "$DEF"
