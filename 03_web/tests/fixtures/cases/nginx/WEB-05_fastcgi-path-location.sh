#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 경로가 지정된 location /cgi-bin/ 에서만 fastcgi_pass
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
insert_before_last "$DEF" '    location /cgi-bin/ {
        fastcgi_pass 127.0.0.1:9000;
        include fastcgi_params;
    }'
assert grep -q 'location /cgi-bin/' "$DEF"
assert nginx -t
