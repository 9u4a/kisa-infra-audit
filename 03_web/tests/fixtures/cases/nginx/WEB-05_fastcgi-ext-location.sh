#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 확장자만으로 매칭하는 location ~ \.php$ 에 fastcgi_pass(어느 디렉터리의 스크립트든 실행)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
insert_before_last "$DEF" '    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        include fastcgi_params;
    }'
assert grep -q 'location ~ \\.php\$' "$DEF"
assert nginx -t
