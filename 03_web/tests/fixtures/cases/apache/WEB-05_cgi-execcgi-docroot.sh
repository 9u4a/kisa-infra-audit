#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: cgid/cgi 모듈 로드 + 문서 루트(htdocs) <Directory> 에 ExecCGI - 지정하지 않은 디렉터리에서 CGI 실행 가능
# FIX: SKIP WEB-05 자동 조치 미구현(fixes/WEB-05.sh 없음) - CGI 를 지정 디렉터리로 옮기는 것은 콘텐츠·URL 이전이 필요해 운영자가 수동 조치
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)#\(LoadModule cgid\{0,1\}_module \)|\1\2|' "$CONF"
assert grep -qE '^[[:space:]]*LoadModule cgid?_module' "$CONF"
sed -i 's|^\([[:space:]]*\)Options Indexes FollowSymLinks$|\1Options Indexes FollowSymLinks ExecCGI|' "$CONF"
assert grep -q 'Options Indexes FollowSymLinks ExecCGI' "$CONF"
assert httpd -t
