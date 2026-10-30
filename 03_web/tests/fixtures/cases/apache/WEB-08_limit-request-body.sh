#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: LimitRequestBody 10MB 로 업로드 용량 제한
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
printf '\nLimitRequestBody 10485760\n' >> "$CONF"
assert grep -q '^LimitRequestBody 10485760' "$CONF"
assert httpd -t
