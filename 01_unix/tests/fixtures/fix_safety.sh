#!/bin/sh
# 01_unix/tests/fixtures/fix_safety.sh — 컨테이너 안에서 실행. KEY=VALUE 로 출력하고 판정은 run_tests.sh 가 한다.
# vuln 상태 → run.sh → fix.sh --apply --yes(비대화형이라 confirm 등급은 건너뜀, auto 만 적용)
# → 결과 → --rollback → 핵심 설정 파일의 내용·권한·소유자가 조치 전과 같은지.
set -u
sh 01_unix/tests/fixtures/setup.sh vuln >/dev/null 2>&1
FILES="/etc/passwd /etc/shadow /etc/group /etc/login.defs /etc/ssh/sshd_config /etc/security/pwquality.conf /etc/pam.d/su /etc/hosts"
snap() {
    for f in $FILES; do
        [ -e "$f" ] && printf '%s %s %s\n' "$f" "$(cksum < "$f")" "$(stat -c '%a %U:%G' "$f")"
    done
}
BEFORE=$(snap)

sh 01_unix/run.sh -e debian -o /tmp/runout >/dev/null 2>&1
R=$(ls /tmp/runout/*/result.json)
sh 01_unix/fix.sh -r "$R" -o /tmp/fixout --apply --yes > /tmp/fix.log 2>&1 < /dev/null
echo "FIX_RC=$?"
grep -qE 'parameter not set|unbound variable' /tmp/fix.log && echo "CRASH=yes" || echo "CRASH=no"
LOG=$(ls /tmp/fixout/*_01_fix_*/changes.log)
echo "APPLIED=$(grep -c "$(printf '\tAPPLIED\t')" "$LOG")"
# U-01 은 1.3.0 부터 confirm 등급이라 비대화형 일괄 적용에서는 확인 단계에서 건너뛴다(DECLINED)
# changes.log 형식: 시각<TAB>코드<TAB>등급<TAB>결과<TAB>상세
echo "U01=$(awk -F'\t' '$2 == "U-01" { print $4 }' "$LOG")"

# U-01 안전장치: root 외 관리자(sudo/wheel 구성원)가 없으면 sshd_config 를 바꾸지 않아야 한다 -
# 확인 단계를 거치지 않도록 조치 함수를 직접 호출해 검증한다.
SSHD_BEFORE=$(cksum < /etc/ssh/sshd_config)
U01_GUARD=$(LIB_DIR=lib sh -c '
    . lib/common.sh; OS_FAMILY=debian; FIX_CODE=U-01; FIX_BACKUP_DIR=/tmp/u01guard; FIX_LOG=/dev/null
    mkdir -p "$FIX_BACKUP_DIR"; . 01_unix/fixes/U-01.sh; run_fix; echo "$FIX_STATUS"' 2>/dev/null | tail -n1)
[ "$SSHD_BEFORE" = "$(cksum < /etc/ssh/sshd_config)" ] && echo "U01_GUARD=$U01_GUARD/unchanged" || echo "U01_GUARD=$U01_GUARD/changed"

sh 01_unix/fix.sh -o /tmp/fixout --rollback "$(dirname "$LOG")" >/dev/null 2>&1 < /dev/null
AFTER=$(snap)
if [ "$BEFORE" = "$AFTER" ]; then
    echo "ROLLBACK=same"
else
    echo "ROLLBACK=diff"
    printf '%s\n' "$BEFORE" > /tmp/b; printf '%s\n' "$AFTER" > /tmp/a
    diff /tmp/b /tmp/a | grep '^[<>]' | sed 's/^/DIFF=/'
fi
