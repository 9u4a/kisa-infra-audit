#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: SSL 을 켜고 평문 가상호스트 두 개 중 a 에만 https 리다이렉트 - b 는 평문 그대로 서비스
#       (1.5.0 A20: 예전에는 파일 어딘가에 리다이렉트 줄이 있으면 GOOD)
# FIX: GOOD 서버 전역에 <If HTTPS != on> Redirect 추가 - 모든 가상호스트가 물려받음
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
self_signed /usr/local/apache2/conf/server.crt /usr/local/apache2/conf/server.key
sed -i -e 's|^#\(LoadModule ssl_module \)|\1|' -e 's|^#\(LoadModule socache_shmcb_module \)|\1|' \
    -e 's|^#\(Include conf/extra/httpd-ssl.conf\)|\1|' "$CONF"
printf '\n<VirtualHost *:80>\n    ServerName a.example.com\n    Redirect permanent / https://a.example.com/\n</VirtualHost>\n<VirtualHost *:80>\n    ServerName b.example.com\n</VirtualHost>\n' >> "$CONF"
assert grep -q '^Include conf/extra/httpd-ssl.conf' "$CONF"
assert grep -q 'Redirect permanent / https://a.example.com/' "$CONF"
assert grep -q 'ServerName b.example.com' "$CONF"
assert httpd -t
