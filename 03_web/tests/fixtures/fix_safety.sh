#!/bin/sh
# 03_web/tests/fixtures/fix_safety.sh <apache|nginx> <apply|backupfail>
# 컨테이너 안에서 실행. 결과를 KEY=VALUE 줄로 출력하고 판정은 run_tests.sh 가 한다.
#   apply      : 취약 상태 → fix.sh --apply --yes → 설정 문법 검사 → --rollback → 원본과 동일한지
#   backupfail : 백업 공간 부족(작은 tmpfs) → 백업 실패 시 설정을 바꾸지 않고 중단하는지
# 비대화형(</dev/null)이라 confirm 등급 항목은 항상 건너뛴다(auto 등급만 적용됨).
set -u
ENGINE=$1
MODE=$2
OUT=${FIX_OUT:-/tmp/fixout}

sh 03_web/tests/fixtures/setup.sh "$ENGINE" vuln >/dev/null 2>&1
sh 03_web/run.sh -e "$ENGINE" -o /tmp/runout >/dev/null 2>&1
R=$(ls /tmp/runout/*/result.json)
case "$ENGINE" in
    apache) CONF=/usr/local/apache2/conf/httpd.conf; TEST="httpd -t" ;;
    nginx) CONF=/etc/nginx/nginx.conf; TEST="nginx -t" ;;
esac
BEFORE=$(cksum < "$CONF")

case "$MODE" in
    apply)
        sh 03_web/fix.sh -r "$R" -o "$OUT" --apply --yes > /tmp/fix.log 2>&1 < /dev/null
        echo "FIX_RC=$?"
        $TEST >/dev/null 2>&1
        echo "SYNTAX_RC=$?"
        echo "APPLIED=$(grep -c "$(printf '\tAPPLIED\t')" "$OUT"/*_03_fix_*/changes.log)"
        sh 03_web/fix.sh -o "$OUT" --rollback "$(ls -d "$OUT"/*_03_fix_*)" >/dev/null 2>&1 < /dev/null
        [ "$BEFORE" = "$(cksum < "$CONF")" ] && echo "ROLLBACK=same" || echo "ROLLBACK=diff"
        ;;
    backupfail)
        sh 03_web/fix.sh -r "$R" -o "$OUT" -i WEB-04 --apply --yes > /tmp/fix.log 2>&1 < /dev/null
        echo "FIX_RC=$?"
        [ "$BEFORE" = "$(cksum < "$CONF")" ] && echo "CONF=unchanged" || echo "CONF=changed"
        echo "ABORTED=$(grep -c ABORTED "$OUT"/*_03_fix_*/changes.log 2>/dev/null)"
        ;;
esac
