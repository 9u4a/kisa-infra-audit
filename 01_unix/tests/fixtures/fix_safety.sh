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
# X-07(1.3.4): U-01 은 sshd -t 가 통과해야만 바꾼다 - 컨테이너에는 /run/sshd 가 없어 sshd -t 가 항상 실패하므로 실제 서버처럼 만든다
mkdir -p /run/sshd
r=$(direct_fix U-01); rb=$(direct_rollback U-01)
[ "$SSHD_BEFORE" = "$(cksum < /etc/ssh/sshd_config)" ] && echo "U01_SSHD=$r/rb-$rb/same" || echo "U01_SSHD=$r/rb-$rb/diff"

# ---- X-07(1.3.4) U-01 F2: 변경 후 sshd -t 검증을 할 수 없으면 바꾸지 않는다 ----------------------------------------
# 기존 설정이 이미 sshd -t 실패 → ERROR·변경 없음 / sshd 명령 없음 → SKIPPED·변경 없음.
cp -p /etc/ssh/sshd_config /tmp/sshd_config.orig
echo "KisaBogusKeyword yes" >> /etc/ssh/sshd_config
SSHD_BAD=$(cksum < /etc/ssh/sshd_config)
r=$(direct_fix U-01)
[ "$SSHD_BAD" = "$(cksum < /etc/ssh/sshd_config)" ] && echo "U01_BADBASE=$r/unchanged" || echo "U01_BADBASE=$r/changed"
direct_rollback U-01 >/dev/null
cp -p /tmp/sshd_config.orig /etc/ssh/sshd_config
SSHD_BIN=$(command -v sshd); mv "$SSHD_BIN" "$SSHD_BIN.kisa_off"
r=$(direct_fix U-01)
[ "$SSHD_BEFORE" = "$(cksum < /etc/ssh/sshd_config)" ] && echo "U01_NOSSHD=$r/unchanged" || echo "U01_NOSSHD=$r/changed"
direct_rollback U-01 >/dev/null
mv "$SSHD_BIN.kisa_off" "$SSHD_BIN"

# ---- X-07(1.3.4) sed -i 금지: PAM 파일이 심볼릭 링크여도(RHEL authselect 배치 등) 조치·원복 뒤 링크가 유지된다 --------
# U-06 은 /etc/pam.d/su 의 주석 처리된 "auth required pam_wheel.so" 를 sed 로 푼다. sed -i 였다면 링크가 일반 파일로
# 바뀌고 실제 파일은 그대로 남아, 원복(cp -p)해도 링크가 돌아오지 않았다.
groupadd -g 4100 wheel 2>/dev/null
sed -i 's/^\(wheel:[^:]*:[^:]*:\)$/\1kisaadm/' /etc/group
mv /etc/pam.d/su /etc/pam.d/su.kisa_real && ln -s su.kisa_real /etc/pam.d/su
SU_BEFORE=$(cksum < /etc/pam.d/su.kisa_real)
r=$(direct_fix U-06)
[ -L /etc/pam.d/su ] && a="link" || a="file"
grep -qE '^auth[[:space:]]+required[[:space:]]+pam_wheel\.so' /etc/pam.d/su.kisa_real && w="target-written" || w="target-not-written"
rb=$(direct_rollback U-06)
[ -L /etc/pam.d/su ] && b="link" || b="file"
[ "$SU_BEFORE" = "$(cksum < /etc/pam.d/su.kisa_real)" ] && c="same" || c="diff"
echo "PAM_SYMLINK=$r/$a/$w/rb-$rb/$b/$c"

# ---- X-04(1.3.4) 조치 격리: 조치가 중간에 죽어도 그 항목만 원복·FAILED 기록 후 다음 항목으로 넘어간다 ---------------
# 테스트 컨테이너 안에서만 U-16 조치를 가짜로 바꿔치기한다: 백업 → 대상 변경 → 미설정 변수(set -u 로 즉사).
# 예전에는(. "$fix_file"; run_fix 를 fix.sh 셸에서 실행) fix.sh 전체가 죽어 대상이 반쯤 바뀐 채 남고 changes.log 에
# 아무 기록도 없었으며 U-18 은 처리되지 않았다.
cp 01_unix/fixes/U-16.sh /tmp/U-16.sh.orig
printf 'kisa-iso-before\n' > /etc/kisa_iso_target
ISO_BEFORE=$(cksum < /etc/kisa_iso_target)
cat > 01_unix/fixes/U-16.sh <<'EOF_FAKE'
run_fix() {
    fix_backup /etc/kisa_iso_target
    printf 'kisa-half-changed\n' >> /etc/kisa_iso_target
    echo "$KISA_UNDEFINED_VAR_X04"
    FIX_STATUS="APPLIED"; FIX_DETAIL="여기에 도달하면 안 됨"
}
EOF_FAKE
sh 01_unix/fix.sh -r "$R" -o /tmp/fixiso -i U-16,U-18 --apply --yes > /tmp/fixiso.log 2>&1 < /dev/null
echo "ISO_RC=$?"
ISOLOG=$(ls /tmp/fixiso/*_01_fix_*/changes.log)
echo "ISO=$(awk -F'\t' '$2 == "U-16" || $2 == "U-18" { printf "%s:%s,", $2, $4 }' "$ISOLOG")"
grep -q 'KISA_UNDEFINED_VAR_X04' "$ISOLOG" && echo "ISO_REASON=logged" || echo "ISO_REASON=missing"
[ "$ISO_BEFORE" = "$(cksum < /etc/kisa_iso_target)" ] && echo "ISO_TARGET=restored" || echo "ISO_TARGET=changed"
# U-18 을 다시 취약 상태로 되돌려 아래 검사(다음 항목 미변경·X-06 변경 없음)가 실제 변경을 감지할 수 있게 한다
sh 01_unix/fix.sh -o /tmp/fixiso --rollback "$(dirname "$ISOLOG")" >/dev/null 2>&1 < /dev/null

# fix_abort_item(백업 실패 등) 규약: 서브셸 안에서 중단해도 이 항목 원복 + ABORTED + fix.sh 종료코드 3, 다음 항목은 손대지 않음
cat > 01_unix/fixes/U-16.sh <<'EOF_FAKE'
run_fix() {
    fix_backup /etc/kisa_iso_target
    printf 'kisa-half-changed\n' >> /etc/kisa_iso_target
    fix_abort_item "테스트용 중단(X-04)"
}
EOF_FAKE
SHADOW_PERM=$(stat -c '%a' /etc/shadow)
sh 01_unix/fix.sh -r "$R" -o /tmp/fixabort -i U-16,U-18 --apply --yes > /tmp/fixabort.log 2>&1 < /dev/null
echo "ABORT_RC=$?"
ABLOG=$(ls /tmp/fixabort/*_01_fix_*/changes.log)
echo "ABORT=$(awk -F'\t' '$2 == "U-16" || $2 == "U-18" { printf "%s:%s,", $2, $4 }' "$ABLOG")"
[ "$ISO_BEFORE" = "$(cksum < /etc/kisa_iso_target)" ] && echo "ABORT_TARGET=restored" || echo "ABORT_TARGET=changed"
[ "$SHADOW_PERM" = "$(stat -c '%a' /etc/shadow)" ] && echo "ABORT_NEXT=untouched" || echo "ABORT_NEXT=changed"
cp /tmp/U-16.sh.orig 01_unix/fixes/U-16.sh

# ---- X-06(1.3.4) result.json 대상 확인: 다른 호스트의 결과 → exit 2·변경 없음 / --force 면 진행 / 7일 경과 → 비대화형 exit 2 -----
sed 's/^\(  "host": "\)[^"]*"/\1kisa-other-host"/' "$R" > /tmp/r_other.json
SNAP_T=$(snap)
sh 01_unix/fix.sh -r /tmp/r_other.json -o /tmp/fixother -i U-18 --apply --yes > /tmp/fixother.log 2>&1 < /dev/null
_rc=$?
[ "$SNAP_T" = "$(snap)" ] && echo "TARGET_HOST=$_rc/unchanged" || echo "TARGET_HOST=$_rc/changed"
sed 's/^\(  "category": "\)[^"]*"/\1DBMS"/' "$R" > /tmp/r_cat.json
sh 01_unix/fix.sh -r /tmp/r_cat.json -o /tmp/fixother -i U-18 --apply --yes > /dev/null 2>&1 < /dev/null
echo "TARGET_CAT=$?"
sed 's/^\(  "generated_at": "\)[^"]*"/\12020-01-01T00:00:00+0000"/' "$R" > /tmp/r_old.json
SNAP_T=$(snap)
sh 01_unix/fix.sh -r /tmp/r_old.json -o /tmp/fixother -i U-18 --apply --yes > /dev/null 2>&1 < /dev/null
_rc=$?
[ "$SNAP_T" = "$(snap)" ] && echo "TARGET_OLD=$_rc/unchanged" || echo "TARGET_OLD=$_rc/changed"
sh 01_unix/fix.sh -r /tmp/r_other.json -o /tmp/fixforce -i U-18 --apply --yes --force > /dev/null 2>&1 < /dev/null
echo "TARGET_FORCE=$?/$(awk -F'\t' '$2 == "U-18" { print $4 }' /tmp/fixforce/*_01_fix_*/changes.log 2>/dev/null)"
