#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: conf-enabled/security.conf(마지막에 읽힘)의 ServerTokens OS -> Prod
. 03_web/tests/fixtures/cases/case_lib.sh
SEC=/etc/apache2/conf-available/security.conf
sed -i 's|^ServerTokens OS|ServerTokens Prod|' "$SEC"
assert grep -q '^ServerTokens Prod' "$SEC"
assert_not grep -rq '^ServerTokens OS' /etc/apache2/conf-enabled/
assert apache2ctl -t
