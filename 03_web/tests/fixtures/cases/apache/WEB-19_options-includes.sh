#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 문서 루트 Options 에 Includes(SSI) 활성
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)Options Indexes FollowSymLinks$|\1Options Indexes FollowSymLinks Includes|' "$CONF"
assert grep -q 'Options Indexes FollowSymLinks Includes' "$CONF"
assert httpd -t
