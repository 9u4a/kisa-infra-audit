#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 가상호스트 두 개 중 a 에만 ErrorDocument 404 - b 와 서버 전역에는 없음(기본 오류 페이지 노출)
#       (1.5.0 A20: 예전에는 파일 어딘가에 ErrorDocument 404 가 있으면 GOOD)
# FIX: GOOD 서버 전역에 ErrorDocument 404 추가 - b 가 물려받음
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
printf '\n<VirtualHost *:80>\n    ServerName a.example.com\n    ErrorDocument 404 "Not Found"\n</VirtualHost>\n<VirtualHost *:80>\n    ServerName b.example.com\n</VirtualHost>\n' >> "$CONF"
assert grep -q '    ErrorDocument 404 "Not Found"' "$CONF"
assert_not grep -qE '^ErrorDocument' "$CONF"
assert httpd -t
