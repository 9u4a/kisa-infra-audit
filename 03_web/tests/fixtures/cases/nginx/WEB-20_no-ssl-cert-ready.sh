#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: listen ssl 없음(기본 default.conf) + 인증서·키 준비 → 1.7.0 값 지정 조치: conf.d 에 listen 443 ssl 서버 블록 파일
# FIX: GOOD
# PARAM: WEB-20.cert = /srv/kisa_tls/server.crt
# PARAM: WEB-20.key = /srv/kisa_tls/server.key
# VERIFY: grep -q 'listen 443 ssl;' /etc/nginx/conf.d/kisa-web20-ssl.conf && grep -q 'root /usr/share/nginx/html;' /etc/nginx/conf.d/kisa-web20-ssl.conf
. 03_web/tests/fixtures/cases/case_lib.sh
mkdir -p /srv/kisa_tls
self_signed /srv/kisa_tls/server.crt /srv/kisa_tls/server.key
assert test -s /srv/kisa_tls/server.crt
