#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: SSL 미설정(기본 httpd.conf, mod_ssl 주석) + 운영자가 인증서·키를 /srv/kisa_tls 에 준비해 둠
# 1.7.0 값 지정 조치: 정책 값으로 mod_ssl 로드 + Listen 443 + <VirtualHost _default_:443> SSLEngine on 추가 → 문법 검사 통과·재진단 양호
# FIX: GOOD
# PARAM: WEB-20.cert = /srv/kisa_tls/server.crt
# PARAM: WEB-20.key = /srv/kisa_tls/server.key
# VERIFY: grep -q '^LoadModule ssl_module' /usr/local/apache2/conf/httpd.conf && grep -q 'SSLCertificateFile "/srv/kisa_tls/server.crt"' /usr/local/apache2/conf/httpd.conf
. 03_web/tests/fixtures/cases/case_lib.sh
mkdir -p /srv/kisa_tls
self_signed /srv/kisa_tls/server.crt /srv/kisa_tls/server.key
assert test -s /srv/kisa_tls/server.crt
assert_not grep -qiE '^[^#]*SSLEngine[[:space:]]+on' /usr/local/apache2/conf/httpd.conf
