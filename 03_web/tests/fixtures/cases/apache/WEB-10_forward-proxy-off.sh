#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: mod_proxy 를 로드했지만 ProxyRequests Off 이고 ProxyPass 없음 - 모듈 로드만으로 VULN 이 되지 않는지(1.4.1 Q-03)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i 's|^\([[:space:]]*\)#\(LoadModule proxy_module \)|\1\2|' "$CONF"
assert grep -qE '^[[:space:]]*LoadModule proxy_module' "$CONF"
printf '\nProxyRequests Off\n' >> "$CONF"
assert_not grep -qiE '^[^#]*(ProxyPass|ProxyRequests[[:space:]]+On)' "$CONF"
assert httpd -t
