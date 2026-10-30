#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 모든 Options 에서 FollowSymLinks 제거(Options None)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)Options Indexes FollowSymLinks$|\1Options None|' "$CONF"
assert_not grep -qiE '^[^#]*Options[^#]*(FollowSymLinks|[[:space:]]All)' "$CONF"
assert grep -qE '^[[:space:]]*Options None' "$CONF"
assert httpd -t
