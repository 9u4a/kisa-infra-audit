#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: a2enmod proxy 했지만 ProxyRequests Off 이고 ProxyPass 없음 - 모듈 활성만으로 VULN 이 되지 않는지(1.4.1 Q-03)
. 03_web/tests/fixtures/cases/case_lib.sh
VHOST=/etc/apache2/sites-available/000-default.conf
enmod() { for m in "$@"; do [ -e "/etc/apache2/mods-available/$m" ] && ln -sf "../mods-available/$m" "/etc/apache2/mods-enabled/$m"; done; }
enmod proxy.load proxy.conf
insert_before "$VHOST" '</VirtualHost>' '	ProxyRequests Off'
assert test -L /etc/apache2/mods-enabled/proxy.load
assert_not grep -rqiE '^[^#]*(ProxyPass|ProxyRequests[[:space:]]+On)' /etc/apache2/apache2.conf /etc/apache2/sites-enabled/ /etc/apache2/conf-enabled/ /etc/apache2/mods-enabled/
assert apache2ctl -t
