#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: a2enmod ssl + a2ensite default-ssl(SSLEngine on) - 인증서(snakeoil) 없는 이미지라 문법 검사는 하지 않음
. 03_web/tests/fixtures/cases/case_lib.sh
enmod() { for m in "$@"; do [ -e "/etc/apache2/mods-available/$m" ] && ln -sf "../mods-available/$m" "/etc/apache2/mods-enabled/$m"; done; }
enmod ssl.load ssl.conf socache_shmcb.load
ln -sf ../sites-available/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf
assert grep -q 'SSLEngine on' /etc/apache2/sites-enabled/default-ssl.conf
