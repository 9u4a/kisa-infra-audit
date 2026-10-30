#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 로그 폴더 750, 기타 사용자 권한 없음
. 03_web/tests/fixtures/cases/case_lib.sh
chmod 0750 /usr/local/apache2/logs
find /usr/local/apache2/logs -type f -exec chmod o-rwx {} +
assert test "$(stat -c %a /usr/local/apache2/logs)" = 750
