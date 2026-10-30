#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 80 가상호스트에 Redirect permanent / https://
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
VHOST=/etc/apache2/sites-available/000-default.conf
insert_before "$VHOST" '</VirtualHost>' '	Redirect permanent / https://www.example.com/'
assert grep -q 'Redirect permanent / https://' "$VHOST"
assert apache2ctl -t
