#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: /var/log/apache2 폴더 755 + 로그 파일 644(기타 사용자 읽기)
. 03_web/tests/fixtures/cases/case_lib.sh
chmod 0755 /var/log/apache2
: > /var/log/apache2/access.log
chmod 0644 /var/log/apache2/access.log
assert test "$(stat -c %a /var/log/apache2)" = 755
