#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: Debian apache2 기본(ssl 모듈 미사용) + 인증서·키 준비 → 1.7.0 값 지정 조치: mods-enabled 에 ssl·socache_shmcb 링크 + VirtualHost 443
# FIX: GOOD
# PARAM: WEB-20.cert = /srv/kisa_tls/server.crt
# PARAM: WEB-20.key = /srv/kisa_tls/server.key
# VERIFY: test -L /etc/apache2/mods-enabled/ssl.load && grep -q 'SSLEngine on' /etc/apache2/apache2.conf
. 03_web/tests/fixtures/cases/case_lib.sh
mkdir -p /srv/kisa_tls
self_signed /srv/kisa_tls/server.crt /srv/kisa_tls/server.key
assert test -s /srv/kisa_tls/server.crt
assert_not test -e /etc/apache2/mods-enabled/ssl.load
