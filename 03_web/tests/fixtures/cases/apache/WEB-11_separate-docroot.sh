#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: DocumentRoot 를 기본 경로(htdocs)가 아닌 별도 경로(/srv/www)로 분리
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
mkdir -p /srv/www
sed -i 's|"/usr/local/apache2/htdocs"|"/srv/www"|g' "$CONF"
assert grep -q '^DocumentRoot "/srv/www"' "$CONF"
assert_not grep -q '^[^#]*/usr/local/apache2/htdocs' "$CONF"
assert httpd -t
