#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: ServerTokens Prod
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
printf '\nServerTokens Prod\nServerSignature Off\n' >> "$CONF"
assert grep -q '^ServerTokens Prod' "$CONF"
assert httpd -t
