#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 공식 이미지 기본 default.conf 그대로 - server 블록에 error_page 500 502 503 504 만 있어 404 는 기본 페이지(버전 노출).
#       그 블록은 바깥(http) error_page 를 물려받지 않는다(실무 적용 검증 P-05: 예전에는 error_page 줄만 보고 GOOD)
# FIX: GOOD 그 블록의 error_page 바로 뒤에 error_page 404 추가
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
printf '# kisa case: 기본 error_page(50x) 만 있는 상태\n' >> "$DEF"
assert grep -qE '^[[:space:]]*error_page[[:space:]]+500' "$DEF"
assert_not grep -qE '^[^#]*error_page[^;]*[[:space:]]404' "$DEF" "$CONF"
