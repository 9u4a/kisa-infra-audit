# U-02 (상) 비밀번호 관리정책 설정
# 판단 기준(가이드 원문): 양호 = 비밀번호 관리 정책(복잡성·주기)이 설정된 경우
# 자동화 범위: LINUX(rhel/debian) 의 /etc/login.defs(주기) + pwquality.conf(복잡성)만 판정.

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse)
            logindefs="/etc/login.defs"
            pwquality="/etc/security/pwquality.conf"
            evidence=""
            ok_count=0
            checks_total=0

            if [ -f "$logindefs" ]; then
                max_days=$(grep -E '^[[:space:]]*PASS_MAX_DAYS' "$logindefs" 2>/dev/null | awk '{print $2}' | tail -n1)
                min_days=$(grep -E '^[[:space:]]*PASS_MIN_DAYS' "$logindefs" 2>/dev/null | awk '{print $2}' | tail -n1)
                evidence="$evidence
$logindefs: PASS_MAX_DAYS=${max_days:-미설정} PASS_MIN_DAYS=${min_days:-미설정}"
                checks_total=$((checks_total + 1))
                if [ -n "$max_days" ] && [ "$max_days" -le 90 ] 2>/dev/null; then
                    ok_count=$((ok_count + 1))
                fi
            fi

            if [ -f "$pwquality" ]; then
                minlen=$(grep -E '^[[:space:]]*minlen' "$pwquality" 2>/dev/null | tail -n1 | sed -E 's/[^0-9]*([0-9]+).*/\1/')
                evidence="$evidence
$pwquality: minlen=${minlen:-미설정}"
                checks_total=$((checks_total + 1))
                if [ -n "$minlen" ] && [ "$minlen" -ge 8 ] 2>/dev/null; then
                    ok_count=$((ok_count + 1))
                fi
            fi

            if [ "$checks_total" -eq 0 ]; then
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="login.defs / pwquality.conf 파일을 찾을 수 없어 자동 판정 불가"
            elif [ "$ok_count" -eq "$checks_total" ]; then
                CHECK_STATUS="GOOD"
                CHECK_DETAIL="비밀번호 주기(90일 이하) 및 최소 길이(8자 이상) 정책이 설정됨"
            elif [ "$ok_count" -eq 0 ]; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="비밀번호 주기·복잡성 정책이 설정되어 있지 않음"
            else
                CHECK_STATUS="MANUAL"
                CHECK_DETAIL="일부 정책만 설정됨 (주기 또는 복잡성 중 하나 누락) — 수동 확인 필요"
            fi
            CHECK_EVIDENCE=$(printf '%s' "$evidence" | sed '/^$/d')
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현 (0.2.0에서 SOLARIS/AIX/HP-UX 지원 예정)"
            CHECK_EVIDENCE=""
            ;;
    esac
}
