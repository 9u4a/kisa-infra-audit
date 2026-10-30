#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: location / 에 dav_methods PUT DELETE(WebDAV 활성)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i '0,/location \/ {/s//location \/ {\n        dav_methods PUT DELETE;/' "$DEF"
assert grep -q 'dav_methods PUT DELETE;' "$DEF"
assert nginx -t
