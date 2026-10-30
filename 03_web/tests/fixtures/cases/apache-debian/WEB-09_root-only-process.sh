#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: apache2 프로세스가 전부 root(배포판 빌드는 User root 기동을 거부하므로 같은 이름의 root 프로세스로 재현)
# FIX: SKIP 가짜 root 프로세스로 재현한 상태라 조치(User 지정 + graceful)의 재검증이 실제 상태를 반영하지 않음 - 조치 경로는 nginx WEB-09 케이스가 실제 프로세스로 검증
. 03_web/tests/fixtures/cases/case_lib.sh
fake_proc apache2
assert all_root apache2
