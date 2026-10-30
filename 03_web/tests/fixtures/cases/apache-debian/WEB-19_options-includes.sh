#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 가상호스트 <Directory /var/www/html> 에 Options +Includes
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
insert_before "$VHOST" '</VirtualHost>' '	<Directory /var/www/html>
		Options +Includes
	</Directory>'
assert grep -q 'Options +Includes' "$VHOST"
assert apache2ctl -t
