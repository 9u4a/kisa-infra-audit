#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: Alias/ScriptAlias(가상 디렉터리) 없음 - 기본 ScriptAlias /cgi-bin/ 주석 처리
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)\(ScriptAlias /cgi-bin/\)|\1#\2|' "$CONF"
assert_not grep -qiE '^[^#]*(Script)?Alias(Match)?[[:space:]]+/' "$CONF"
assert httpd -t
