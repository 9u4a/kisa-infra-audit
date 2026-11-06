#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 기본 80 server 블록만 https 로 리다이렉트 - 새 평문 server 블록(8081)은 그대로 서비스
#       (1.5.0 A20: 예전에는 파일 어딘가에 return 301 https 가 있으면 GOOD)
# FIX: NONE Nginx 리다이렉트는 넣을 server 블록을 텍스트 치환만으로 안전하게 특정할 수 없어 수동 안내(ERROR, 설정 무변경)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i '0,/server_name[^;]*;/s//&\n    return 301 https:\/\/$host$request_uri;/' "$DEF"
printf 'server {\n    listen 8081;\n    server_name b.example.com;\n    location / { root /usr/share/nginx/html; }\n}\n' > /etc/nginx/conf.d/kisa_b.conf
assert grep -q 'return 301 https://\$host\$request_uri;' "$DEF"
assert nginx -t
