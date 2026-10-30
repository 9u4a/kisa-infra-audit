#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: SSL(httpd-ssl.conf, ServerName 있음)은 켰지만 HTTP->HTTPS 리다이렉트 없음 - 조치가 리다이렉트를 넣을 수 있는 상태
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
self_signed /usr/local/apache2/conf/server.crt /usr/local/apache2/conf/server.key
sed -i -e 's|^#\(LoadModule ssl_module \)|\1|' -e 's|^#\(LoadModule socache_shmcb_module \)|\1|' \
    -e 's|^#\(Include conf/extra/httpd-ssl.conf\)|\1|' "$CONF"
assert grep -q '^LoadModule ssl_module' "$CONF"
assert grep -q '^Include conf/extra/httpd-ssl.conf' "$CONF"
assert httpd -t
assert_not grep -rqiE '^[^#]*Redirect[^#]*https://' /usr/local/apache2/conf
