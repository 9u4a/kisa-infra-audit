#!/bin/sh
# lib/tests/policy_parse_test.sh — 조치 정책 파일(1.6.0 G-01·G-02) 해석·검증 단위 테스트(POSIX sh, 대상 변경 없음).
# 저장소 루트에서 실행: sh lib/tests/policy_parse_test.sh   (CI static-analysis job)
# lib/common_fix.sh 의 fix_policy_args_check·fix_policy_load·fix_policy_approved·fix_policy_irrev_ok 를 직접 부른다. 호스트 이름은
# host_name 을 다시 정의해 바꾼다. 정상 해석(호스트 구역 선택·제외·irreversible·BOM/CRLF)과 거부(exit 2 + 줄 번호)를 확인한다.
set -u
cd "$(dirname "$0")/../.." || exit 1
LIB_DIR=lib
# shellcheck disable=SC1091
. lib/common.sh
GUIDE_JSON=01_unix/guide.json
CATEGORY_NUM=01
T=$(mktemp -d 2>/dev/null || { d="${TMPDIR:-/tmp}/kisa_policy_$$"; mkdir -p "$d" && echo "$d"; })
trap 'rm -rf "$T"' EXIT
TODAY=$(date '+%Y-%m-%d')
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
ng() { fail=$((fail + 1)); echo "FAIL: $1"; }

# load <정책 파일> <호스트> — 서브셸에서 fix_policy_load 실행. 표준출력: rc|section|codes|irrev|excl|approver|expires, 표준오류는 $T/err
load() {
    (
        _lh=$2; host_name() { echo "$_lh"; }
        POLICY_SET=1; POLICY_FILE=$1; POLICY_OPERATOR=tester
        fix_policy_load
        printf '0|%s|%s|%s|%s|%s|%s\n' "$POLICY_SECTION" "$POLICY_CODES" "$POLICY_IRREV" "$POLICY_EXCL" "$POLICY_APPROVER" "$POLICY_EXPIRES"
    ) 2> "$T/err" || printf '%s|\n' "$?"
}
expect_ok() {   # <이름> <파일> <호스트> <기대 출력>
    _r=$(load "$2" "$3")
    if [ "$_r" = "$4" ]; then ok "$1"; else ng "$1 - 기대 [$4] 실제 [$_r] $(tr '\n' ' ' < "$T/err")"; fi
}
expect_rej() {  # <이름> <파일> <호스트> <오류에 있어야 할 문구(grep -F)>
    _r=$(load "$2" "$3")
    if [ "$_r" = "2|" ] && grep -qF -- "$4" "$T/err"; then ok "$1"; else ng "$1 - 기대 exit 2 + [$4], 실제 [$_r] $(tr '\n' ' ' < "$T/err")"; fi
}

# ---- 정상 ----------------------------------------------------------------------------------------
cat > "$T/base" <<'EOF'
# 주석
category=01
expires=2099-12-31
approver=홍길동
U-01
  U-05:irreversible

U-18

[host:web01]
-U-05

[host:*]
-U-18
EOF
expect_ok "정상 - 이름이 맞는 구역(web01) 선택·제외" "$T/base" web01 "0|web01| U-01 U-05 U-18 | U-05 | U-05 |홍길동|2099-12-31"
expect_ok "정상 - 호스트 이름 대소문자 무시" "$T/base" WEB01 "0|web01| U-01 U-05 U-18 | U-05 | U-05 |홍길동|2099-12-31"
expect_ok "정상 - 맞는 구역이 없으면 [host:*] 의 제외 적용" "$T/base" db02 "0|*| U-01 U-05 U-18 | U-05 | U-18 |홍길동|2099-12-31"
# BOM + CRLF
printf '\357\273\277' > "$T/bomcrlf"; sed 's/$/\r/' "$T/base" >> "$T/bomcrlf"
expect_ok "정상 - UTF-8 BOM + CRLF" "$T/bomcrlf" web01 "0|web01| U-01 U-05 U-18 | U-05 | U-05 |홍길동|2099-12-31"
# 오늘까지 유효, 승인 코드 0개도 형식상 허용(전부 POLICY_SKIPPED)
printf 'category=01\nexpires=%s\napprover=a b\n[host:*]\n' "$TODAY" > "$T/today"
expect_ok "정상 - expires=오늘(그날까지 유효)·승인 0건" "$T/today" any "0|*| | | |a b|$TODAY"

# ---- 거부(exit 2, 줄 번호) ---------------------------------------------------------------------------
mk() { _f="$T/$1"; shift; printf '%s\n' "$@" > "$_f"; }
mk cat 'category=03' 'expires=2099-12-31' 'approver=x' 'U-01' '[host:*]'
expect_rej "category 불일치" "$T/cat" h "$T/cat:1): category=03 는 이 조치 카테고리(01)와 다름"
mk exp 'category=01' 'expires=2000-01-01' 'approver=x' 'U-01' '[host:*]'
expect_rej "유효기간 경과" "$T/exp" h "$T/exp:2): 정책 유효기간이 지났음"
mk expfmt 'category=01' 'expires=2099-13-01' 'approver=x' '[host:*]'
expect_rej "expires 형식 오류(13월)" "$T/expfmt" h "$T/expfmt:2): expires 는 YYYY-MM-DD"
mk expfmt2 'category=01' 'expires=2099/12/31' 'approver=x' '[host:*]'
expect_rej "expires 형식 오류(구분자)" "$T/expfmt2" h "expires 는 YYYY-MM-DD"
mk dup 'category=01' 'expires=2099-12-31' 'approver=x' 'U-01' '# 주석' 'U-01:irreversible' '[host:*]'
expect_rej "같은 코드 중복(줄 6)" "$T/dup" h "$T/dup:6): 같은 코드가 두 번 나옴: U-01"
mk nocode 'category=01' 'expires=2099-12-31' 'approver=x' 'U-99' '[host:*]'
expect_rej "guide.json 에 없는 코드" "$T/nocode" h "$T/nocode:4): 이 카테고리 guide.json 에 없는 코드: U-99"
mk othercat 'category=01' 'expires=2099-12-31' 'approver=x' 'W-01' '[host:*]'
expect_rej "다른 카테고리 코드" "$T/othercat" h "guide.json 에 없는 코드: W-01"
mk badcode 'category=01' 'expires=2099-12-31' 'approver=x' 'u-01' '[host:*]'
expect_rej "코드 형식 오류(소문자)" "$T/badcode" h "$T/badcode:4): 형식 오류"
mk badflag 'category=01' 'expires=2099-12-31' 'approver=x' 'U-01:force' '[host:*]'
expect_rej "알 수 없는 플래그" "$T/badflag" h "$T/badflag:4): 형식 오류"
mk key 'category=01' 'expires=2099-12-31' 'approver=x' 'mode=auto' '[host:*]'
expect_rej "알 수 없는 키" "$T/key" h "$T/key:4): 알 수 없는 키: mode"
mk dupkey 'category=01' 'category=01' 'expires=2099-12-31' 'approver=x' '[host:*]'
expect_rej "머리말 키 중복" "$T/dupkey" h "$T/dupkey:2): category= 가 두 번 나옴"
mk noappr 'category=01' 'expires=2099-12-31' 'U-01' '[host:*]'
expect_rej "approver 없음" "$T/noappr" h "$T/noappr:-): 머리말에 approver= 가 없음"
mk emptyappr 'category=01' 'expires=2099-12-31' 'approver=  ' '[host:*]'
expect_rej "approver 비어 있음" "$T/emptyappr" h "$T/emptyappr:3): approver 가 비어 있음"
mk nohost 'category=01' 'expires=2099-12-31' 'approver=x' 'U-01' '[host:web01]' '-U-01'
expect_rej "호스트 미등록([host:*] 없음)" "$T/nohost" db02 "정책에 없는 호스트: db02"
mk sectcode 'category=01' 'expires=2099-12-31' 'approver=x' '[host:*]' 'U-01'
expect_rej "호스트 구역 안의 승인 코드" "$T/sectcode" h "$T/sectcode:5): 호스트 구역에는"
mk sectkey 'category=01' 'expires=2099-12-31' 'approver=x' '[host:*]' 'approver=y'
expect_rej "호스트 구역 안의 키=값" "$T/sectkey" h "$T/sectkey:5): 호스트 구역에는"
mk excldup 'category=01' 'expires=2099-12-31' 'approver=x' '[host:*]' '-U-01' '-U-01'
expect_rej "같은 구역 제외 중복" "$T/excldup" h "$T/excldup:6): 같은 구역에서 같은 코드를 두 번 제외함: U-01"
mk keycase 'Category=01' 'expires=2099-12-31' 'approver=x' '[host:*]'
expect_rej "머리말 키 대소문자 구분" "$T/keycase" h "$T/keycase:1): 알 수 없는 키: Category"
mk flagcase 'category=01' 'expires=2099-12-31' 'approver=x' 'U-01:IRREVERSIBLE' '[host:*]'
expect_rej ":irreversible 대소문자 구분" "$T/flagcase" h "$T/flagcase:4): 형식 오류"
mk exclbad 'category=01' 'expires=2099-12-31' 'approver=x' '[host:*]' '-U-99'
expect_rej "제외 코드가 guide.json 에 없음" "$T/exclbad" h "$T/exclbad:5): 이 카테고리 guide.json 에 없는 코드: U-99"
mk badsect 'category=01' 'expires=2099-12-31' 'approver=x' '[hosts:web01]'
expect_rej "구역 형식 오류" "$T/badsect" h "$T/badsect:4): 구역 형식 오류"
mk emptysect 'category=01' 'expires=2099-12-31' 'approver=x' '[host:]'
expect_rej "빈 호스트 이름" "$T/emptysect" h "호스트 이름이 비어 있음"
mk dupsect 'category=01' 'expires=2099-12-31' 'approver=x' '[host:web01]' '[host:WEB01]'
expect_rej "같은 호스트 구역 중복" "$T/dupsect" web01 "$T/dupsect:5): 같은 호스트 구역이 두 번 나옴"
mk multi 'category=02' 'expires=2099-12-31' 'approver=x' 'U-99' '[host:*]'
_r=$(load "$T/multi" h)
if [ "$_r" = "2|" ] && grep -qF "$T/multi:1)" "$T/err" && grep -qF "$T/multi:4)" "$T/err"; then ok "오류 여러 건을 모두 보고"; else ng "오류 여러 건 보고 - $(tr '\n' ' ' < "$T/err")"; fi
_r=$(load "$T/없는파일" h)
if [ "$_r" = "2|" ] && grep -qF "정책 파일을 읽을 수 없습니다" "$T/err"; then ok "정책 파일 없음"; else ng "정책 파일 없음 - [$_r]"; fi

# ---- 옵션 조합(fix_policy_args_check) ---------------------------------------------------------------
args() {   # <POLICY_SET> <POLICY_FILE> <OPERATOR_SET> <OPERATOR> <ROLLBACK_DIR> → rc
    ( POLICY_SET=$1; POLICY_FILE=$2; POLICY_OPERATOR_SET=$3; POLICY_OPERATOR=$4; fix_policy_args_check "$5" ) 2>/dev/null; echo $?
}
[ "$(args 1 "$T/base" 0 "" "")" = 2 ] && ok "--policy 만(--operator 없음) → exit 2" || ng "--policy 만"
[ "$(args 1 "$T/base" 1 "   " "")" = 2 ] && ok "--operator 공백 → exit 2" || ng "--operator 공백"
[ "$(args 0 "" 1 "kim" "")" = 2 ] && ok "--operator 만(--policy 없음) → exit 2" || ng "--operator 만"
[ "$(args 1 "" 1 "kim" "")" = 2 ] && ok "--policy 빈 경로 → exit 2" || ng "--policy 빈 경로"
[ "$(args 1 "$T/base" 1 "kim" "/tmp/x")" = 0 ] && ok "--policy + --rollback → 정책 무시(원복만)" || ng "--policy + --rollback"
[ "$(args 0 "" 1 "kim" "/tmp/x")" = 2 ] && ok "--operator 단독 + --rollback → exit 2" || ng "--operator 단독 + --rollback"
[ "$(args 1 "$T/base" 1 "$(printf 'kim\tx')" "")" = 2 ] && ok "--operator 에 탭 → exit 2" || ng "--operator 탭"
[ "$(args 1 "$T/base" 1 "$(printf 'kim\033x')" "")" = 2 ] && ok "--operator 에 제어 문자(ESC) → exit 2" || ng "--operator ESC"
[ "$(args 1 "$T/base" 1 "$(printf 'kim\nx')" "")" = 2 ] && ok "--operator 에 줄바꿈 → exit 2" || ng "--operator 줄바꿈"
[ "$(args 1 "$T/base" 1 "김 철수" "")" = 0 ] && ok "--policy + --operator 정상" || ng "--policy + --operator 정상"
[ "$(args 0 "" 0 "" "")" = 0 ] && ok "정책 옵션 없음(대화형 모드) 통과" || ng "정책 옵션 없음"

# ---- 승인 판정(fix_policy_approved·fix_policy_irrev_ok) ------------------------------------------------
printf '# U-90 테스트\n# 변경: x\nrun_fix() { :; }\n' > "$T/plain.sh"
printf '# U-90 테스트\n# 변경: x\n# 원복: 불가 - 테스트\nrun_fix() { :; }\n' > "$T/rb.sh"
printf '# U-90 테스트\n# 변경: x\n# 영향: 서비스 중지 - 테스트\nrun_fix() { :; }\n' > "$T/im.sh"
decide() {  # <호스트> <코드> <조치 파일> → approved/irrev 결과 + 사유
    (
        _dh=$1; host_name() { echo "$_dh"; }
        POLICY_SET=1; POLICY_FILE="$T/base"; POLICY_OPERATOR=tester
        fix_policy_load 2>/dev/null
        if ! fix_policy_approved "$2"; then echo "SKIP:$POLICY_REASON"; exit 0; fi
        if ! fix_policy_irrev_ok "$2" "$3"; then echo "SKIP:$POLICY_REASON"; exit 0; fi
        echo "APPLY"
    )
}
[ "$(decide db02 U-01 "$T/plain.sh")" = "APPLY" ] && ok "승인·표기 없음 → 적용" || ng "승인·표기 없음"
[ "$(decide db02 U-02 "$T/plain.sh")" = "SKIP:정책 미승인" ] && ok "미승인 → 정책 미승인" || ng "미승인 [$(decide db02 U-02 "$T/plain.sh")]"
[ "$(decide db02 U-18 "$T/plain.sh")" = "SKIP:정책 미승인(호스트 제외: [host:*])" ] && ok "[host:*] 제외" || ng "[host:*] 제외 [$(decide db02 U-18 "$T/plain.sh")]"
[ "$(decide WEB01 U-05 "$T/rb.sh")" = "SKIP:정책 미승인(호스트 제외: [host:web01])" ] && ok "[host:web01] 제외(irreversible 보다 우선)" || ng "[host:web01] 제외 [$(decide WEB01 U-05 "$T/rb.sh")]"
[ "$(decide db02 U-01 "$T/rb.sh")" = "SKIP:irreversible 플래그 필요: 원복: 불가 - 테스트" ] && ok "원복 표기 + 플래그 없음 → 건너뜀" || ng "원복 표기 [$(decide db02 U-01 "$T/rb.sh")]"
[ "$(decide db02 U-01 "$T/im.sh")" = "SKIP:irreversible 플래그 필요: 영향: 서비스 중지 - 테스트" ] && ok "영향 표기 + 플래그 없음 → 건너뜀" || ng "영향 표기 [$(decide db02 U-01 "$T/im.sh")]"
[ "$(decide db02 U-05 "$T/im.sh")" = "APPLY" ] && ok "영향 표기 + :irreversible → 적용" || ng "영향 + irreversible"
[ "$(decide db02 U-05 "$T/rb.sh")" = "APPLY" ] && ok "원복 표기 + :irreversible → 적용" || ng "원복 + irreversible"

# ---- SHA-256 ---------------------------------------------------------------------------------------
_h=$(fix_sha256 "$T/base")
if command -v sha256sum >/dev/null 2>&1; then _e=$(sha256sum "$T/base" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then _e=$(shasum -a 256 "$T/base" | awk '{ print $1 }')
else _e=$(openssl dgst -sha256 "$T/base" | awk '{ print $NF }'); fi
[ -n "$_h" ] && [ "$_h" = "$_e" ] && ok "SHA-256 ($_h)" || ng "SHA-256 [$_h] != [$_e]"
# SHA-256 도구가 하나도 없으면 정책 모드 거부(PATH 를 비워 흉내)
_r=$( ( host_name() { echo h; }; PATH=/nonexistent; POLICY_SET=1; POLICY_FILE="$T/base"; fix_policy_load ) 2>&1; echo "rc=$?")
case "$_r" in *"SHA-256 도구"*"rc=2") ok "SHA-256 도구 없음 → exit 2" ;; *) ng "SHA-256 도구 없음 [$_r]" ;; esac

echo "------------------------------------------------------------------------"
echo "policy_parse_test: PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
