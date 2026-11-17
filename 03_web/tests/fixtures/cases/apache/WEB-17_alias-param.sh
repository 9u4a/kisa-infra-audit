#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# MANUAL: 기본 ScriptAlias /cgi-bin/ + 추가한 Alias /kisa-old (불필요 여부는 업무 판단)
# 1.7.0 값 지정 조치: 정책 값의 /kisa-old 만 주석 처리 → /cgi-bin/ 이 남아 재진단 MANUAL
# FIX: MANUAL
# PARAM: WEB-17.aliases = /kisa-old
# VERIFY: grep -q '^# KISA WEB-17 Alias /kisa-old' /usr/local/apache2/conf/httpd.conf && grep -q '^[[:space:]]*ScriptAlias /cgi-bin/' /usr/local/apache2/conf/httpd.conf
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
mkdir -p /srv/old
printf 'Alias /kisa-old "/srv/old"\n<Directory "/srv/old">\n    Require all granted\n</Directory>\n' >> "$CONF"
assert grep -q '^Alias /kisa-old' "$CONF"
assert httpd -t
