#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: a2enmod cgid + 가상호스트 문서 루트(/var/www/html) <Directory> 에 Options +ExecCGI
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
enmod() { for m in "$@"; do [ -e "/etc/apache2/mods-available/$m" ] && ln -sf "../mods-available/$m" "/etc/apache2/mods-enabled/$m"; done; }
enmod cgid.load cgid.conf
insert_before "$VHOST" '</VirtualHost>' '	<Directory /var/www/html>
		Options +ExecCGI
	</Directory>'
assert test -L /etc/apache2/mods-enabled/cgid.load
assert grep -q 'Options +ExecCGI' "$VHOST"
assert apache2ctl -t
