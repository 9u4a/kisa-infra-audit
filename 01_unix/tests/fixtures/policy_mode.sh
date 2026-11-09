#!/bin/sh
# 01_unix/tests/fixtures/policy_mode.sh — 조치 정책 모드(1.6.0 G-01·G-02·G-03) 실기. 컨테이너 안에서 실행하고 KEY=VALUE 로
# 출력한다(판정은 run_tests.sh). 비대화형(< /dev/null, --yes 없음)에서:
#   ① 정책 거부(카테고리 불일치·유효기간 경과·호스트 미등록·--operator 없음, --force 로도 우회 불가)는 exit 2·변경 없음
#   ② dry-run 도 정책 판정(적용 예정/정책 미승인/irreversible 플래그 필요)을 보여 주고 아무것도 바꾸지 않음
#   ③ --apply: 승인된 confirm 항목(U-67)이 y/N 없이 적용, 미승인(U-11)·호스트 제외(U-16)·플래그 없는 원복(U-34)/영향(U-05)
#      표기 항목은 POLICY_SKIPPED, U-36:irreversible 은 적용. 실패 경로: U-12(confirm)는 vuln 픽스처의 profile.d TMOUT=0 이
#      /etc/profile 값을 덮어써 재검증 VULN → 원복(FAILED_ROLLED_BACK) - 무인 실행에서도 다음 항목을 계속하고 요약·감사 기록에
#      failed_codes 로 남는지 본다(U-12 조치가 profile.d 까지 고치게 되면 이 기대값을 함께 바꿀 것)
#   ④ audit.txt·changes.log 맨 앞 감사 기록(operator·login_user·approver·policy_file·policy_sha256·started_at·finished_at·건수)
set -u
sh 01_unix/tests/fixtures/setup.sh vuln >/dev/null 2>&1
sh 01_unix/run.sh -e debian -o /tmp/runout >/dev/null 2>&1
R=$(ls /tmp/runout/*/result.json)
# 조치 대상 상태 스냅샷(U-12 /etc/profile, U-18 /etc/shadow, U-16 /etc/passwd, U-11 계정 쉘)
snap() { printf '%s|%s|%s|%s\n' "$(cksum < /etc/profile)" "$(stat -c '%a' /etc/shadow)" "$(stat -c '%a' /etc/passwd)" "$(cksum < /etc/passwd)"; }

P=/tmp/policy.txt
cat > "$P" <<'EOF'
# 1.6.0 정책 모드 실기
category=01
expires=2099-12-31
approver=홍길동
U-18
U-16
U-12
U-67
U-05
U-34
U-36:irreversible

[host:*]
-U-16
EOF

# ---- ① 거부: exit 2, 변경 없음 ----------------------------------------------------------------------------
BEFORE=$(snap)
sed 's/^category=01/category=03/' "$P" > /tmp/p_cat.txt
sh 01_unix/fix.sh -r "$R" -o /tmp/fixrej --policy /tmp/p_cat.txt --operator 김점검 --apply < /dev/null > /tmp/rej_cat.log 2>&1
echo "REJ_CAT=$?/$(grep -c 'category=03' /tmp/rej_cat.log)"
sh 01_unix/fix.sh -r "$R" -o /tmp/fixrej --policy /tmp/p_cat.txt --operator 김점검 --apply --force < /dev/null > /dev/null 2>&1
echo "REJ_CAT_FORCE=$?"
sed 's/^expires=.*/expires=2001-01-01/' "$P" > /tmp/p_exp.txt
sh 01_unix/fix.sh -r "$R" -o /tmp/fixrej --policy /tmp/p_exp.txt --operator 김점검 --apply < /dev/null > /tmp/rej_exp.log 2>&1
echo "REJ_EXP=$?/$(grep -c 'p_exp.txt:3): 정책 유효기간이 지났음' /tmp/rej_exp.log)"
sed 's/^\[host:\*\]/[host:kisa-other-host]/' "$P" > /tmp/p_host.txt
sh 01_unix/fix.sh -r "$R" -o /tmp/fixrej --policy /tmp/p_host.txt --operator 김점검 --apply < /dev/null > /tmp/rej_host.log 2>&1
echo "REJ_HOST=$?/$(grep -c '정책에 없는 호스트' /tmp/rej_host.log)"
sh 01_unix/fix.sh -r "$R" -o /tmp/fixrej --policy "$P" --apply < /dev/null > /dev/null 2>&1
echo "REJ_NOOP=$?"
sh 01_unix/fix.sh -r "$R" -o /tmp/fixrej --operator 김점검 --apply < /dev/null > /dev/null 2>&1
echo "REJ_OPONLY=$?"
# 거부된 실행은 출력 폴더(<host>_01_fix_*)도 만들지 않아야 한다
if [ "$BEFORE" = "$(snap)" ] && [ -z "$(ls /tmp/fixrej 2>/dev/null | grep _fix_)" ]; then echo "REJ_STATE=unchanged"; else echo "REJ_STATE=changed"; fi

# ---- ② dry-run: 정책 판정 미리보기, 변경 없음 -----------------------------------------------------------------
sh 01_unix/fix.sh -r "$R" -o /tmp/fixdry --policy "$P" --operator 김점검 < /dev/null > /tmp/dry.log 2>&1
echo "DRY_RC=$?"
DLOG=$(ls /tmp/fixdry/*_01_fix_*/changes.log)
echo "DRY_PREVIEW_U12=$(awk '/^\[U-12\]/ { f = 1; next } /^\[/ { f = 0 } f && /정책: 적용 예정/ { print "yes"; exit }' /tmp/dry.log)"
echo "DRY_SKIP=$(awk -F'\t' '$4 == "POLICY_SKIPPED" && ($2 == "U-05" || $2 == "U-11" || $2 == "U-16" || $2 == "U-34") { printf "%s,", $2 }' "$DLOG")"
echo "DRY_MODE=$(grep '^mode=' "$(dirname "$DLOG")/audit.txt")"
[ "$BEFORE" = "$(snap)" ] && echo "DRY_STATE=unchanged" || echo "DRY_STATE=changed"

# ---- ③ --apply (비대화형, --yes 없음) -----------------------------------------------------------------------
sh 01_unix/fix.sh -r "$R" -o /tmp/fixpol --policy "$P" --operator 김점검 --apply < /dev/null > /tmp/pol.log 2>&1
echo "POL_RC=$?"
LOG=$(ls /tmp/fixpol/*_01_fix_*/changes.log)
AUD="$(dirname "$LOG")/audit.txt"
st() { awk -F'\t' -v c="$1" '$2 == c { print $4 }' "$LOG"; }
rs() { awk -F'\t' -v c="$1" '$2 == c { print $5 }' "$LOG"; }
for c in U-18 U-12 U-67 U-36 U-16 U-05 U-34 U-11; do echo "POL_$c=$(st "$c")"; done
case "$(rs U-11)" in "정책 미승인") echo "WHY_U-11=unapproved" ;; *) echo "WHY_U-11=$(rs U-11)" ;; esac
case "$(rs U-16)" in "정책 미승인(호스트 제외: [host:*])") echo "WHY_U-16=excluded" ;; *) echo "WHY_U-16=$(rs U-16)" ;; esac
case "$(rs U-34)" in "irreversible 플래그 필요: 원복: "*) echo "WHY_U-34=irrev-rollback" ;; *) echo "WHY_U-34=$(rs U-34)" ;; esac
case "$(rs U-05)" in "irreversible 플래그 필요: 영향: "*) echo "WHY_U-05=irrev-impact" ;; *) echo "WHY_U-05=$(rs U-05)" ;; esac
# 확인 질문이 한 번도 나오지 않았는지(DECLINED 0건, "[y/N]" 출력 없음)
echo "POL_PROMPTS=$(grep -c '\[y/N\]' /tmp/pol.log)/$(awk -F'\t' '$4 == "DECLINED"' "$LOG" | wc -l | tr -d ' ')"
[ "$(stat -c '%a' /etc/shadow)" = "400" ] && echo "POL_U18_STATE=400" || echo "POL_U18_STATE=$(stat -c '%a' /etc/shadow)"
grep -q '^TMOUT=600' /etc/profile && echo "POL_U12_STATE=TMOUT" || echo "POL_U12_STATE=rolled-back"
grep -q '^실패 항목: U-12 ' /tmp/pol.log && echo "POL_FAILED_SUMMARY=U-12" || echo "POL_FAILED_SUMMARY=missing"

# ---- ④ 감사 기록 -------------------------------------------------------------------------------------------
kv() { sed -n "s/^$1=//p" "$AUD" | head -n 1; }
echo "AUD_OPERATOR=$(kv operator)"
echo "AUD_APPROVER=$(kv approver)"
echo "AUD_LOGIN=$(kv login_user)"
echo "AUD_FILE=$(kv policy_file)"
[ "$(kv policy_sha256)" = "$(sha256sum "$P" | awk '{ print $1 }')" ] && echo "AUD_SHA=match" || echo "AUD_SHA=mismatch"
echo "AUD_EXPIRES=$(kv policy_expires)"
echo "AUD_HOST=$([ "$(kv host)" = "$(hostname)" ] && echo match || echo mismatch)"
echo "AUD_CAT=$(kv category)/$(kv mode)"
kv started_at | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$' && echo "AUD_START=iso" || echo "AUD_START=$(kv started_at)"
kv finished_at | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' && echo "AUD_END=iso" || echo "AUD_END=missing"
echo "AUD_FAILED_CODES=$(kv failed_codes)"
echo "AUD_COUNTS=applied:$(kv applied),failed:$(kv failed),policy_skipped_ge4:$([ "$(kv policy_skipped)" -ge 4 ] 2>/dev/null && echo yes || echo no)"
# changes.log 맨 앞이 감사 기록과 같은 줄로 시작하는지
[ "$(head -n 1 "$LOG")" = "# operator=김점검" ] && head -n 12 "$LOG" | grep -qx "# policy_sha256=$(kv policy_sha256)" && echo "LOG_HEAD=audit" || echo "LOG_HEAD=$(head -n 1 "$LOG")"
tail -n 10 "$LOG" | grep -q '^# finished_at=' && echo "LOG_TAIL=finished" || echo "LOG_TAIL=missing"
grep -q "정책으로 건너뜀" /tmp/pol.log && echo "SUMMARY=policy" || echo "SUMMARY=missing"
