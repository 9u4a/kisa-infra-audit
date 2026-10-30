#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: root 를 /srv/www 로 분리
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
mkdir -p /srv/www
sed -i 's|/usr/share/nginx/html|/srv/www|g' "$DEF"
assert_not grep -q '/usr/share/nginx/html' "$DEF"
assert nginx -t
