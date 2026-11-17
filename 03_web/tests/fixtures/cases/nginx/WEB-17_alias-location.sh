#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# MANUAL: location /virtual/ { alias ... } 가상 디렉터리 존재(불필요 여부는 업무 판단)
# 1.7.0 값 지정 조치: 정책 값 /virtual/ 의 location 블록을 통째로 주석 처리 → 가상 디렉터리 없음, 재진단 양호
# FIX: GOOD
# PARAM: WEB-17.aliases = /virtual/
# VERIFY: grep -q '^# KISA WEB-17 .*location /virtual/' /etc/nginx/conf.d/default.conf && ! grep -qE '^[^#]*alias /srv/virtual/' /etc/nginx/conf.d/default.conf
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
mkdir -p /srv/virtual
insert_before_last "$DEF" '    location /virtual/ {
        alias /srv/virtual/;
    }'
assert grep -q 'alias /srv/virtual/;' "$DEF"
assert nginx -t
