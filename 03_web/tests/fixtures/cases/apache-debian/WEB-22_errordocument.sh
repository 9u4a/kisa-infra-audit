#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: apache2.conf 에 ErrorDocument 지정
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
printf '\nErrorDocument 404 "Not Found"\nErrorDocument 500 "Error"\n' >> "$CONF"
assert grep -q '^ErrorDocument 404' "$CONF"
assert apache2ctl -t
