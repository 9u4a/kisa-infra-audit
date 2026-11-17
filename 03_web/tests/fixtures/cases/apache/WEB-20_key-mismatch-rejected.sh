#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: SSL 미설정 + 정책 값의 키가 인증서와 짝이 아님 → 1.7.0 값 검증 실패, 아무것도 바꾸지 않음
# FIX: NONE 개인 키가 인증서와 짝이 아니면 값 검증에서 거부
# PARAM: WEB-20.cert = /srv/kisa_tls/a.crt
# PARAM: WEB-20.key = /srv/kisa_tls/b.key
. 03_web/tests/fixtures/cases/case_lib.sh
mkdir -p /srv/kisa_tls
self_signed /srv/kisa_tls/a.crt /srv/kisa_tls/a.key
self_signed /srv/kisa_tls/b.crt /srv/kisa_tls/b.key
assert test -s /srv/kisa_tls/b.key
