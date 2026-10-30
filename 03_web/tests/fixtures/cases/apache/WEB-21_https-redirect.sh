#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: HTTP 요청을 https:// 로 영구 리다이렉트
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
printf '\nRedirect permanent / https://www.example.com/\n' >> "$CONF"
assert grep -q '^Redirect permanent / https://' "$CONF"
assert httpd -t
