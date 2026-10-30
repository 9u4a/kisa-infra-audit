#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: /var/log/nginx 폴더 750(로그 파일은 표준출력 링크)
. 03_web/tests/fixtures/cases/case_lib.sh
chmod 0750 /var/log/nginx
find /var/log/nginx -maxdepth 1 -type f -exec chmod o-rwx {} +
assert test "$(stat -c %a /var/log/nginx)" = 750
