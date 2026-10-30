#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: httpd 실제 기동 - 마스터 root, worker 는 User daemon
. 03_web/tests/fixtures/cases/case_lib.sh
httpd -k start
wait_until 15 has_nonroot httpd
