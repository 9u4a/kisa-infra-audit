#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 기본 index.html/50x.html 제거
. 03_web/tests/fixtures/cases/case_lib.sh
rm -f /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html
assert_not test -e /usr/share/nginx/html/index.html
