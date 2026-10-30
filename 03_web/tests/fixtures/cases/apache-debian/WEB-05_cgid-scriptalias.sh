#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: a2enmod cgid - Debian 기본 serve-cgi-bin.conf 의 ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/ 의 <Directory> 에서만 +ExecCGI
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
enmod() { for m in "$@"; do [ -e "/etc/apache2/mods-available/$m" ] && ln -sf "../mods-available/$m" "/etc/apache2/mods-enabled/$m"; done; }
enmod cgid.load cgid.conf
assert test -L /etc/apache2/mods-enabled/cgid.load
assert test -L /etc/apache2/conf-enabled/serve-cgi-bin.conf
assert grep -q 'ScriptAlias /cgi-bin/ /usr/lib/cgi-bin/' /etc/apache2/conf-available/serve-cgi-bin.conf
assert apache2ctl -t
