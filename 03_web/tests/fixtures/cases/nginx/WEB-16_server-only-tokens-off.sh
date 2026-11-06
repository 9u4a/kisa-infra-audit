#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 기본 server 블록에만 server_tokens off - 새 server 블록(8081)은 기본값 on(버전 노출)
#       (1.5.0 A20: 예전에는 파일 어딘가에 off 가 있으면 GOOD)
# FIX: GOOD http 블록에 server_tokens off 추가 - 모든 server 블록이 물려받음
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i '0,/server_name[^;]*;/s//&\n    server_tokens off;/' "$DEF"
printf 'server {\n    listen 8081;\n    server_name b.example.com;\n    location / { root /usr/share/nginx/html; }\n}\n' > /etc/nginx/conf.d/kisa_b.conf
assert grep -q 'server_tokens off;' "$DEF"
assert_not grep -q 'server_tokens' "$CONF"
assert nginx -t
