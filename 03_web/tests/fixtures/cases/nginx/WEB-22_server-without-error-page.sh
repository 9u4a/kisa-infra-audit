#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 기본 server 블록은 error_page 404 까지 지정했지만 새 server 블록(8081)과 http 블록에는 error_page 가 없음
#       (1.5.0 A20: 예전에는 error_page 가 있는 블록만 보고 error_page 가 아예 없는 server 블록을 놓쳐 GOOD)
# FIX: GOOD http 블록에 error_page 404 추가 - error_page 없는 server 블록이 물려받음
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
insert_after "$DEF" 'error_page   500 502 503 504' '    error_page   404 /404.html;'
printf 'server {\n    listen 8081;\n    server_name b.example.com;\n    location / { root /usr/share/nginx/html; }\n}\n' > /etc/nginx/conf.d/kisa_b.conf
assert grep -qE '^[[:space:]]*error_page[[:space:]]+404' "$DEF"
assert_not grep -q 'error_page' "$CONF"
assert nginx -t
