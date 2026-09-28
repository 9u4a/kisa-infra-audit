# U-30 (중) UMASK 설정 관리
# 판단 기준(가이드 원문): 양호 = UMASK 값이 022 이상으로 설정된 경우
#                        취약 = 022 미만으로 설정된 경우
# 전 Unix 계열 공통 로직: /etc/profile, /etc/login.defs(Linux) 확인.

run_check() {
    evidence=""
    val=""

    for f in /etc/profile /etc/login.defs; do
        [ -f "$f" ] || continue
        line=$(grep -iE '^[[:space:]]*umask[[:space:]]+[0-7]+' "$f" 2>/dev/null | tail -n1)
        [ -z "$line" ] && continue
        evidence="$evidence
$f: $line"
        val=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[Uu][Mm][Aa][Ss][Kk][[:space:]]+([0-7]+).*/\1/')
    done

    if [ -z "$val" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="/etc/profile, /etc/login.defs 에서 UMASK 설정을 찾지 못함 (기본값 또는 다른 파일에서 설정되었을 수 있음)"
        CHECK_EVIDENCE=""
        return
    fi

    val_num=$(printf '%s' "$val" | sed 's/^0*//')
    [ -z "$val_num" ] && val_num=0

    if [ "$val_num" -ge 22 ] 2>/dev/null; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="UMASK=${val} (022 이상)으로 설정됨"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="UMASK=${val} 로 022 미만으로 설정됨"
    fi
    CHECK_EVIDENCE="$evidence"
}
