#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: listen 443 ssl 서버 블록(자체 서명 테스트 인증서)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
self_signed /etc/nginx/kisa_test.crt /etc/nginx/kisa_test.key
cat > /etc/nginx/conf.d/ssl.conf <<'EOF_SSL'
server {
    listen 443 ssl;
    server_name www.example.com;
    ssl_certificate /etc/nginx/kisa_test.crt;
    ssl_certificate_key /etc/nginx/kisa_test.key;
    root /usr/share/nginx/html;
}
EOF_SSL
assert grep -q 'listen 443 ssl;' /etc/nginx/conf.d/ssl.conf
assert nginx -t
