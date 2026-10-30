#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: cgid/cgi 모듈은 로드하지만 CGI 는 ScriptAlias /cgi-bin/ 디렉터리에서만 실행(ExecCGI 없음)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)#\(LoadModule cgid\{0,1\}_module \)|\1\2|' "$CONF"
assert grep -qE '^[[:space:]]*LoadModule cgid?_module' "$CONF"
assert grep -q '^[[:space:]]*ScriptAlias /cgi-bin/' "$CONF"
assert_not grep -qiE '^[^#]*Options[^#]*(ExecCGI|[[:space:]]All)' "$CONF"
assert httpd -t
