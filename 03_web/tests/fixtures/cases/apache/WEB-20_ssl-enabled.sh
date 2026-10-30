#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: mod_ssl + httpd-ssl.conf(SSLEngine on, 자체 서명 테스트 인증서)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
self_signed /usr/local/apache2/conf/server.crt /usr/local/apache2/conf/server.key
sed -i -e 's|^#\(LoadModule ssl_module \)|\1|' -e 's|^#\(LoadModule socache_shmcb_module \)|\1|' \
    -e 's|^#\(Include conf/extra/httpd-ssl.conf\)|\1|' "$CONF"
assert grep -q '^LoadModule ssl_module' "$CONF"
assert grep -q '^Include conf/extra/httpd-ssl.conf' "$CONF"
assert httpd -t
