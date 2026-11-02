#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: a2enmod proxy proxy_http + 가상호스트에 ProxyRequests On(정방향 오픈 프록시) - 1.4.1 Q-03
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
enmod() { for m in "$@"; do [ -e "/etc/apache2/mods-available/$m" ] && ln -sf "../mods-available/$m" "/etc/apache2/mods-enabled/$m"; done; }
enmod proxy.load proxy.conf proxy_http.load
insert_before "$VHOST" '</VirtualHost>' '	ProxyRequests On'
assert test -L /etc/apache2/mods-enabled/proxy.load
assert grep -q 'ProxyRequests On' "$VHOST"
assert apache2ctl -t
