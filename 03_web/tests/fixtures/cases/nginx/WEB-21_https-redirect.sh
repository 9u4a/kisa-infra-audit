#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 80 서버 블록에 return 301 https://$host$request_uri
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i '0,/server_name[^;]*;/s//&\n    return 301 https:\/\/$host$request_uri;/' "$DEF"
assert grep -q 'return 301 https://\$host\$request_uri;' "$DEF"
assert nginx -t
