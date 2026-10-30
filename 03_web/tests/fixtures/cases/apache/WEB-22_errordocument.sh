#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: ErrorDocument 로 에러 페이지 지정
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
printf '\nErrorDocument 404 "Not Found"\nErrorDocument 500 "Error"\n' >> "$CONF"
assert grep -q '^ErrorDocument 404' "$CONF"
assert httpd -t
