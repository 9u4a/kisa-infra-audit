#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 웹 루트 <Directory> 의 Options 를 상대 지정(-Indexes)만으로 바꿈 - 기본값 FollowSymLinks 가 그대로 상속된다
#       (1.5.0 A19: 예전에는 Options 줄이 하나라도 있으면 기본값을 무시해 GOOD)
# FIX: NONE 켜진 FollowSymLinks 토큰이 없어 줄 단위 조치로 끌 수 없음 - 어느 <Directory> 에 -FollowSymLinks 를 넣을지 수동 안내(ERROR, 설정 무변경)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)Options Indexes FollowSymLinks$|\1Options -Indexes|' "$CONF"
assert grep -qE '^[[:space:]]*Options -Indexes$' "$CONF"
assert_not grep -qiE '^[^#]*Options[^#]*(FollowSymLinks|[[:space:]]All)' "$CONF"
assert httpd -t
