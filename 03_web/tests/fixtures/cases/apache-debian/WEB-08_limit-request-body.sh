#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: apache2.conf 에 LimitRequestBody 10MB
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
printf '\nLimitRequestBody 10485760\n' >> "$CONF"
assert grep -q '^LimitRequestBody 10485760' "$CONF"
assert apache2ctl -t
