# U-02 (상) 비밀번호 관리정책 설정 — 조치
# 가이드 조치 방법: 비밀번호 사용 기간(90일 이하)·최소 길이(8자 이상) 정책 설정
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    logindefs="/etc/login.defs"
    pwquality="/etc/security/pwquality.conf"
    applied=""

    if [ -f "$logindefs" ]; then
        fix_backup "$logindefs"
        if grep -qE '^[[:space:]]*PASS_MAX_DAYS' "$logindefs"; then
            sed -i -E 's/^[[:space:]]*PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' "$logindefs"
        else
            printf 'PASS_MAX_DAYS   90\n' >> "$logindefs"
        fi
        applied="$applied $logindefs(PASS_MAX_DAYS=90)"
    fi

    if [ -f "$pwquality" ]; then
        fix_backup "$pwquality"
        if grep -qE '^[[:space:]]*minlen' "$pwquality"; then
            sed -i -E 's/^[[:space:]]*minlen.*/minlen = 8/' "$pwquality"
        else
            printf 'minlen = 8\n' >> "$pwquality"
        fi
        applied="$applied $pwquality(minlen=8)"
    fi

    if [ -z "$applied" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="login.defs/pwquality.conf 를 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="비밀번호 주기(90일)·최소 길이(8자) 정책 설정:$applied"
    FIX_EVIDENCE="$applied"
}
