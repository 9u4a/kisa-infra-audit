#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: dav_module/dav_fs_module 로드(WebDAV 활성)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/usr/local/apache2/conf/httpd.conf
sed -i -e 's|^#\(LoadModule dav_module \)|\1|' -e 's|^#\(LoadModule dav_fs_module \)|\1|' "$CONF"
assert grep -q '^LoadModule dav_module' "$CONF"
assert httpd -t
