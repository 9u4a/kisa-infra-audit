#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: http 블록에 disable_symlinks on
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i '/http[[:space:]]*{/a\    disable_symlinks on;' "$CONF"
assert grep -q 'disable_symlinks on;' "$CONF"
assert nginx -t
