#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: client_max_body_size 0(무제한)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i '/http[[:space:]]*{/a\    client_max_body_size 0;' "$CONF"
assert grep -q 'client_max_body_size 0;' "$CONF"
assert nginx -t
