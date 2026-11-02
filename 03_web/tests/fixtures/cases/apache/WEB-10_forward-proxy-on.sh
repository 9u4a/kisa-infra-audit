#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: mod_proxy·mod_proxy_http 로드 + ProxyRequests On(정방향 오픈 프록시) - 1.4.1 Q-03
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)#\(LoadModule proxy_module \)|\1\2|; s|^\([[:space:]]*\)#\(LoadModule proxy_http_module \)|\1\2|' "$CONF"
assert grep -qE '^[[:space:]]*LoadModule proxy_module' "$CONF"
printf '\nProxyRequests On\n' >> "$CONF"
assert grep -q '^ProxyRequests On' "$CONF"
assert httpd -t
