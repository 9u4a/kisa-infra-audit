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
# 이 픽스처에는 root 외 관리자(sudo/wheel 구성원)가 없으므로 U-01 은 sshd_config 를 바꾸면 안 된다
echo "U01=$(awk -F'\t' '$1 == "U-01" { print $3 }' "$LOG")"

sh 01_unix/fix.sh -o /tmp/fixout --rollback "$(dirname "$LOG")" >/dev/null 2>&1 < /dev/null
AFTER=$(snap)
if [ "$BEFORE" = "$AFTER" ]; then
    echo "ROLLBACK=same"
else
    echo "ROLLBACK=diff"
    printf '%s\n' "$BEFORE" > /tmp/b; printf '%s\n' "$AFTER" > /tmp/a
    diff /tmp/b /tmp/a | grep '^[<>]' | sed 's/^/DIFF=/'
fi
