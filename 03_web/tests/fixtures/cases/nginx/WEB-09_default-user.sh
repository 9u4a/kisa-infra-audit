#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 기본 설정(user nginx)으로 nginx 실제 기동 - worker 비 root
. 03_web/tests/fixtures/cases/case_lib.sh
nginx
wait_until 15 has_nonroot nginx
