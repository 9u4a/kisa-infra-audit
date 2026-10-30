#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 매뉴얼 디렉터리(/var/www/manual)가 웹 경로에 남아 있음
. 03_web/tests/fixtures/cases/case_lib.sh
mkdir -p /var/www/manual
echo '<html>Apache HTTP Server Documentation</html>' > /var/www/manual/index.html
assert test -f /var/www/manual/index.html
