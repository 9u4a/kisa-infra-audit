# D-05 (중) 비밀번호 재사용에 대한 제약 설정 [Oracle]
# 판단 기준(가이드 원문): 양호 = 비밀번호 재사용 제한 설정을 적용한 경우
#                        취약 = 적용하지 않은 경우
# 프로파일의 PASSWORD_REUSE_TIME/PASSWORD_REUSE_MAX 가 둘 다 UNLIMITED/NULL 이면 취약.
# 진단 검수 D-R5: DEFAULT 프로파일만 보던 것을, 잠기지 않은 계정이 쓰는 모든 프로파일로 넓혔다 -
# 하나라도 제한이 없으면 취약(oracle_profile_limits).
run_check() {
    out=$(oracle_profile_limits "'PASSWORD_REUSE_TIME','PASSWORD_REUSE_MAX'")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="[프로파일|자원|실효값]
$out"
    bad=$(printf '%s\n' "$out" | awk -F'|' '
        NF >= 3 { p=$1; v=$3; gsub(/[ \t\r]/, "", p); gsub(/[ \t\r]/, "", v)
                  seen[p]=1; if (v != "UNLIMITED" && v != "NULL" && v != "") ok[p]=1 }
        END { for (p in seen) if (!(p in ok)) printf "%s ", p }')
    if [ -z "$(printf '%s' "$out" | awk -F'|' 'NF >= 3')" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="프로파일 정보를 읽지 못함(결과 없음)"
    elif [ -z "$bad" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="사용 중인 모든 프로파일에 비밀번호 재사용 제한(PASSWORD_REUSE_TIME/MAX) 설정이 적용되어 있음"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 재사용 제한 설정이 적용되어 있지 않은 프로파일이 있음(UNLIMITED/NULL): $bad"
    fi
}
