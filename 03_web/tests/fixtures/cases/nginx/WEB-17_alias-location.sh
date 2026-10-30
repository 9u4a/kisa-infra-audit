#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# MANUAL: location /virtual/ { alias ... } 가상 디렉터리 존재(불필요 여부는 업무 판단)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
mkdir -p /srv/virtual
insert_before_last "$DEF" '    location /virtual/ {
        alias /srv/virtual/;
    }'
assert grep -q 'alias /srv/virtual/;' "$DEF"
assert nginx -t
