#!/bin/sh
# 01_unix/tests/fixtures/cases/case_run.sh <코드> <이름> <base> <fix 기대(GOOD|MANUAL|NOFIX|-)> — 케이스 1개를 실행(컨테이너 안).
# 결과를 KEY=VALUE 줄로 출력하고 판정은 01_unix/tests/run_cases.sh 가 한다.
#   1) base 픽스처(setup.sh hardened|vuln, none 이면 생략) → 상태 스냅숏 S0
#   2) cases.sh 의 c_<코드>__<이름> 실행 → 스냅숏 S1. S0 = S1 이면 CHANGED=no(케이스 준비가 아무것도 바꾸지 않음 = 실패)
#   3) run.sh -i <코드> → STATUS
#   4) fix 기대가 있으면(VULN 케이스) fix.sh --apply(가상 터미널로 confirm 등급에 y) → FIX=<changes.log 결과>/<재검증>
#      → --rollback → 스냅숏 S2. S1 = S2 이면 ROLLBACK=same(조치 전 취약 상태로 정확히 돌아옴)
set -u
CODE=$1; NAME=$2; BASE=$3; FIXEXP=$4
cd /infra || exit 2

# snap — 파일시스템(경로·종류·권한·소유자·크기 + /etc·/root·/home·/srv·/usr/local·/var 내용 해시, /dev 의 일반 파일) +
# 서비스 상태(케이스가 만든 /etc/systemd/system/*.service 의 enabled/active) + 실행 중인 프로세스 이름 집합.
# systemd 가 계속 바꾸는 저널·상태 파일(/var/log/journal, /var/lib/systemd)은 제외한다.
snap() {
    { find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp -o -path /var/tmp \
            -o -path /var/log/journal -o -path /var/lib/systemd -o -path /var/cache \) -prune -o -printf '%p|%y|%m|%U|%G|%s\n' 2>/dev/null
      find /etc /root /home /srv /usr/local /var -xdev \( -path /var/tmp -o -path /var/log/journal -o -path /var/lib/systemd -o -path /var/cache \) -prune \
            -o -type f -exec md5sum {} + 2>/dev/null | awk '{ print $2 "|md5|" $1 }'
      find /dev -type f -printf '%p|dev|%m|%s\n' 2>/dev/null
      for u in /etc/systemd/system/*.service; do
          [ -f "$u" ] || continue
          u=$(basename "$u")
          printf 'unit|%s|%s|%s\n' "$u" "$(systemctl is-enabled "$u" 2>/dev/null)" "$(systemctl is-active "$u" 2>/dev/null)"
      done
      ps -e -o comm= 2>/dev/null | sed 's/^/proc|/'
    } | grep -vE '^/etc/(passwd|group|shadow|gshadow|subuid|subgid)-\||^/etc/\.pwd\.lock\||^proc\|(ps|sort|find|md5sum|awk|sed|sh|grep|xargs|systemctl|basename|uniq)$' | sort -u
}

# 서비스 유닛이 막 기동된 직후 상태가 흔들리지 않게 잠깐 기다린다(systemd 가 바쁘면 is-active 가 activating 일 수 있음)
settle() { systemctl is-system-running --wait >/dev/null 2>&1 || :; sleep 1; }

fn="c_$(printf '%s' "$CODE" | tr '-' '_')__$(printf '%s' "$NAME" | tr '-' '_')"
# shellcheck disable=SC1091
. 01_unix/tests/fixtures/cases/cases.sh
if ! command -v "$fn" >/dev/null 2>&1; then
    echo "CASE_FN=missing($fn)"
    exit 0
fi
echo "CASE_FN=ok"

[ "$BASE" = "none" ] || sh 01_unix/tests/fixtures/setup.sh "$BASE" >/dev/null 2>&1
settle
snap > /tmp/s0
"$fn" >/tmp/case_setup.log 2>&1
echo "SETUP_RC=$?"
settle
snap > /tmp/s1
if cmp -s /tmp/s0 /tmp/s1; then echo "CHANGED=no"; else echo "CHANGED=yes"; fi

sh 01_unix/run.sh -e debian -i "$CODE" -o /tmp/runout > /tmp/run.log 2>&1
R=$(ls /tmp/runout/*/result.json 2>/dev/null | head -n1)
st=$(sed -n "s/.*\"code\":\"$CODE\",\"status\":\"\([A-Z]*\)\".*/\1/p" "$R" 2>/dev/null | head -n1)
echo "STATUS=${st:-none}"
det=$(sed -n "s/.*\"code\":\"$CODE\",\"status\":\"[A-Z]*\",\"detail\":\"\([^\"]*\)\".*/\1/p" "$R" 2>/dev/null | head -n1 | cut -c1-240)
echo "DETAIL=$det"

[ "$FIXEXP" = "-" ] && exit 0
# 조치 → 재검증(fix.sh 내부) → 원복 → 상태 비교. confirm 등급과 조치 안의 확인(fix_confirm_tty)에 y 를 넣기 위해
# script 로 가상 터미널을 만든다(03_web fix_safety.sh 와 같은 방식).
(while echo y; do sleep 0.3; done) 2>/dev/null | \
    script -qec "sh 01_unix/fix.sh -r '$R' -i '$CODE' -o /tmp/fixout --apply --yes" /dev/null > /tmp/fix.log 2>&1
echo "FIX_RC=$?"
LOG=$(ls /tmp/fixout/*_01_fix_*/changes.log 2>/dev/null | head -n1)
fr=$(awk -F'\t' -v c="$CODE" '$2 == c { print $4 }' "$LOG" 2>/dev/null | tail -n1)
rc=$(awk -F'\t' -v c="$CODE" '$2 == c { print $5 }' "$LOG" 2>/dev/null | tail -n1 | sed -n 's/.*recheck=\([A-Z]*\).*/\1/p')
echo "FIX=${fr:-none}/${rc:-none}"
awk -F'\t' -v c="$CODE" '$2 == c { print "FIXDETAIL=" substr($5, 1, 300) }' "$LOG" 2>/dev/null | tail -n1
sh 01_unix/fix.sh -o /tmp/fixout --rollback "$(dirname "$LOG")" > /tmp/rb.log 2>&1 < /dev/null
echo "RB_RC=$?"
settle
snap > /tmp/s2
if cmp -s /tmp/s1 /tmp/s2; then
    echo "ROLLBACK=same"
else
    echo "ROLLBACK=diff"
    diff /tmp/s1 /tmp/s2 | grep '^[<>]' | head -n 12 | sed 's/^/DIFF=/'
fi
