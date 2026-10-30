#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: user root 로 nginx 실제 기동(마스터·worker 모두 root)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/nginx/nginx.conf
DEF=/etc/nginx/conf.d/default.conf
sed -i 's/^user[[:space:]].*/user  root;/' "$CONF"
assert grep -q '^user  root;' "$CONF"
nginx
wait_until 15 all_root nginx
sleep 1
assert all_root nginx
