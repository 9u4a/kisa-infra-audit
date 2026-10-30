#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 가상호스트 DocumentRoot 를 /srv/www 로 분리
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
mkdir -p /srv/www
sed -i 's|DocumentRoot /var/www/html|DocumentRoot /srv/www|' "$VHOST"
assert grep -q 'DocumentRoot /srv/www' "$VHOST"
assert_not grep -rq '^[^#]*DocumentRoot /var/www' /etc/apache2/apache2.conf /etc/apache2/sites-enabled/ /etc/apache2/conf-enabled/
assert apache2ctl -t
