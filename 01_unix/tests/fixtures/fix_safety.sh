#!/bin/sh
# 01_unix/tests/fixtures/fix_safety.sh — 컨테이너 안에서 실행. KEY=VALUE 로 출력하고 판정은 run_tests.sh 가 한다.
# vuln 상태 → run.sh → fix.sh --apply --yes(비대화형이라 confirm 등급은 건너뜀, auto 만 적용)
# → 결과 → --rollback → 핵심 설정 파일의 내용·권한·소유자가 조치 전과 같은지.
set -u
sh 01_unix/tests/fixtures/setup.sh vuln >/dev/null 2>&1
# 원복 비교 범위: 파일시스템 전체(-xdev, 가상·임시 FS 와 저장소 제외)의 경로·종류·권한·소유자·크기 + /etc·/root·/home·
# /usr/local·/var 일반 파일 내용 해시. 예전에는 8개 파일만 비교해 U-62(/etc/issue.net 백업 없이 덮어씀)·U-09(groupadd 가
# 바꾼 /etc/gshadow 미백업) 원복 누락을 놓쳤다. 예외는 shadow 도구가 남기는 "<파일>-" 백업과 잠금 파일뿐.
snap() {
    { find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp -o -path /var/tmp -o -path /infra \) \
          -prune -o -printf '%p|%y|%m|%U|%G|%s\n' 2>/dev/null
      find /etc /root /home /usr/local /var -xdev -path /var/tmp -prune -o -type f -exec md5sum {} + 2>/dev/null | awk '{ print $2 "|md5|" $1 }'
    } | grep -vE '^/etc/(passwd|group|shadow|gshadow|subuid|subgid)-\||^/etc/\.pwd\.lock\|' | sort
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
# 적용으로 실제 변경이 일어났는지(아무것도 바꾸지 않으면 원복 비교가 무의미)
[ "$BEFORE" != "$(snap)" ] && echo "CHANGED=yes" || echo "CHANGED=no"
# 기대한 항목만 APPLIED 이고, 원복 못 한 항목(FAILED_NOT_ROLLED_BACK)·기대 밖 실패가 없는지 run_tests.sh 가 본다
echo "APPLIED_CODES=$(awk -F'\t' '$4 == "APPLIED" { printf "%s,", $2 }' "$LOG")"
echo "FAILED_CODES=$(awk -F'\t' '$4 ~ /^FAILED|^ABORTED/ { printf "%s:%s,", $2, $4 }' "$LOG")"
echo "SKIPPED_CODES=$(awk -F'\t' '$4 == "SKIPPED" { printf "%s,", $2 }' "$LOG")"
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
    diff /tmp/b /tmp/a | grep '^[<>]' | head -n 40 | sed 's/^/DIFF=/'
fi

# ---- F-R8/F-R9 재현 케이스 -------------------------------------------------------------------
# U-32(auto): Debian 기본 nologin 시스템 계정(list → /var/list 등)의 없는 홈 때문에 예전 조치는 재검증 VULN → 원복이었다.
# 일괄 적용에서 APPLIED 여야 하고, --rollback 뒤에는 조치가 만든 디렉터리가 남지 않아야 한다.
echo "U32=$(awk -F'\t' '$2 == "U-32" { print $4 }' "$LOG")"
[ -e /var/list ] && echo "U32_RB=left" || echo "U32_RB=absent"

# confirm 등급(U-01, U-59~61)은 비대화형 일괄 적용에서 건너뛰므로 조치 함수를 직접 부른다:
# 적용 → 진단 재실행(재검증) → 원복 → 대상 파일이 조치 전과 같은지.
direct_fix() {   # <코드> → "<FIX_STATUS>/<재검증>"
    LIB_DIR=lib sh -c '
        . lib/common.sh; OS_FAMILY=debian; FIX_CODE=$1; FIX_BACKUP_DIR=/tmp/direct_$1; FIX_LOG=/dev/null
        FIX_FILE_DIR=01_unix/fixes; mkdir -p "$FIX_BACKUP_DIR"
        . 01_unix/fixes/$1.sh; run_fix
        run_check_isolated 01_unix/checks/$1.sh
        echo "$FIX_STATUS/$CHECK_STATUS"' _ "$1" 2>/dev/null | tail -n1
}
direct_rollback() {
    LIB_DIR=lib sh -c '
        . lib/common.sh; FIX_BACKUP_DIR=/tmp/direct_$1; FIX_ROLLBACK_FAILS=""; fix_rollback_item "$1"
        rm -rf "/tmp/direct_$1"; [ -z "$FIX_ROLLBACK_FAILS" ] && echo ok || echo "fail:$FIX_ROLLBACK_FAILS"' _ "$1" 2>/dev/null | tail -n1
}
snmp_snap() { for f in /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.d/v2.conf /etc/snmp/kisa-extra.conf; do printf '%s %s %s\n' "$f" "$(cksum < "$f")" "$(stat -c '%a %U:%G %i' "$f")"; done; }

# U-59~61: 주 파일은 v3 뿐, includeDir 의 rocommunity6 public default + includeFile 의 com2sec -Cn·소스 생략 rocommunity
SNMP_BEFORE=$(snmp_snap)
for c in U-61 U-60 U-59; do
    r=$(direct_fix "$c")
    # 결과 파일에 기존 community 원문이 남았는지(U-60 은 모두 바뀌어야 함) - 비밀값은 출력하지 않는다
    extra=""
    [ "$c" = "U-60" ] && grep -qE '(^|[[:space:]])(public|private|weak1)([[:space:]]|$)' /etc/snmp/snmpd.conf.d/v2.conf /etc/snmp/kisa-extra.conf && extra="/old-left"
    [ "$c" = "U-61" ] && ! grep -q '^rocommunity6 public ::1' /etc/snmp/snmpd.conf.d/v2.conf && extra="/v6-not-restricted"
    echo "SNMP_${c}=$r$extra/rb-$(direct_rollback "$c")"
done
[ "$SNMP_BEFORE" = "$(snmp_snap)" ] && echo "SNMP_ROLLBACK=same" || echo "SNMP_ROLLBACK=diff"

# U-01: 대체 관리자가 있어도 Telnet(xinetd.d/telnet disable=no, securetty 없음) 때문에 VULN 이면 sshd 만 고치는 조치는
# 해소하지 못한다 → 아무것도 바꾸지 않고 SKIPPED. Telnet 을 끄면 sshd 조치가 적용·재검증 통과·원복 동일.
sed -i 's/^\(sudo:[^:]*:[^:]*:\)$/\1testvuln/' /etc/group
SSHD_BEFORE=$(cksum < /etc/ssh/sshd_config)
r=$(direct_fix U-01); rb=$(direct_rollback U-01)
[ "$SSHD_BEFORE" = "$(cksum < /etc/ssh/sshd_config)" ] && echo "U01_TELNET=$r/unchanged" || echo "U01_TELNET=$r/changed"
sed -i 's/disable = no/disable = yes/' /etc/xinetd.d/telnet
r=$(direct_fix U-01); rb=$(direct_rollback U-01)
[ "$SSHD_BEFORE" = "$(cksum < /etc/ssh/sshd_config)" ] && echo "U01_SSHD=$r/rb-$rb/same" || echo "U01_SSHD=$r/rb-$rb/diff"
