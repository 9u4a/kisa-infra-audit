# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [Oracle]
# 판단 기준(가이드 원문): "기관 정책에 맞게" 적용되었는지는 완전 자동 판정 불가. 프로파일의
# PASSWORD_LIFE_TIME/PASSWORD_VERIFY_FUNCTION 값을 증적으로 제공한다. 둘 다
# UNLIMITED/NULL(정책 미시행)이면 명백한 취약으로 판단한다.
# 진단 검수 D-R5: DEFAULT 프로파일만 보던 것을, 잠기지 않은 계정이 쓰는 모든 프로파일로 넓혔다
# (oracle_profile_limits - 사용자 정의 프로파일의 'DEFAULT' 값은 DEFAULT 프로파일 값으로 풀어 씀).
run_check() {
    out=$(oracle_profile_limits "'PASSWORD_LIFE_TIME','PASSWORD_VERIFY_FUNCTION','FAILED_LOGIN_ATTEMPTS'")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="[프로파일|자원|실효값]
$out"
    # 프로파일별로 수명·검증함수가 둘 다 미설정이면 그 프로파일을 취약 목록에 넣는다.
    none=$(printf '%s\n' "$out" | awk -F'|' '
        NF >= 3 { p=$1; r=$2; v=$3; gsub(/[ \t\r]/, "", p); gsub(/[ \t\r]/, "", r); gsub(/[ \t\r]/, "", v)
                  seen[p]=1
                  if (r == "PASSWORD_LIFE_TIME" && v != "" && v != "UNLIMITED") ok[p]=1
                  if (r == "PASSWORD_VERIFY_FUNCTION" && v != "" && v != "NULL") ok[p]=1 }
        END { for (p in seen) if (!(p in ok)) printf "%s ", p }')
    nprof=$(printf '%s\n' "$out" | awk -F'|' 'NF >= 3 { gsub(/[ \t\r]/, "", $1); s[$1]=1 } END { n=0; for (p in s) n++; print n }')
    if [ "$nprof" = "0" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="프로파일 정보를 읽지 못함(결과 없음)"
    elif [ -n "$none" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="비밀번호 사용기간·복잡도 검증 정책이 전혀 설정되지 않은 프로파일이 있음: $none"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="정책 시행 메커니즘은 일부 설정됨(사용 중인 프로파일 ${nprof}개) - 구체적 값이 기관 기준에 맞는지 수동 확인 필요"
    fi
}
