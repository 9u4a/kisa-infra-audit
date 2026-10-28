# D-09 (중) 일정 횟수의 로그인 실패 시 이에 대한 잠금정책 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 로그인 시도 횟수를 제한하는 값을 설정한 경우
#                        취약 = 설정하지 않은 경우
# 진단 검수 D-R5: DEFAULT 프로파일만 보던 것을, 잠기지 않은 계정이 쓰는 모든 프로파일로 넓혔다 -
# 하나라도 UNLIMITED 면 취약(oracle_profile_limits).
run_check() {
    out=$(oracle_profile_limits "'FAILED_LOGIN_ATTEMPTS'")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="[프로파일|자원|실효값]
$out"
    bad=$(printf '%s\n' "$out" | awk -F'|' '
        NF >= 3 { p=$1; v=$3; gsub(/[ \t\r]/, "", p); gsub(/[ \t\r]/, "", v)
                  if (v == "UNLIMITED" || v == "") printf "%s ", p }')
    if [ -z "$(printf '%s' "$out" | awk -F'|' 'NF >= 3')" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="프로파일 정보를 읽지 못함(결과 없음)"
    elif [ -n "$bad" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="로그인 실패 횟수 제한(FAILED_LOGIN_ATTEMPTS)이 UNLIMITED 인 프로파일이 있음: $bad"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="사용 중인 모든 프로파일에 로그인 실패 횟수 제한(FAILED_LOGIN_ATTEMPTS)이 설정되어 있음"
    fi
}
