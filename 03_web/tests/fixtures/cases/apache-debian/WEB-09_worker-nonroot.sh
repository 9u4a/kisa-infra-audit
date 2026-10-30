#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: apache2ctl start 실제 기동 - 마스터 root, worker 는 www-data
. 03_web/tests/fixtures/cases/case_lib.sh
apache2ctl start
wait_until 15 has_nonroot apache2
