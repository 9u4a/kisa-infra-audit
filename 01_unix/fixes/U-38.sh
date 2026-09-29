# U-38 (상) DoS 공격에 취약한 서비스 비활성화 — 조치
run_fix() {
    targets="echo discard daytime chargen"
    applied=""

    for svc in $targets; do
        for xf in "/etc/xinetd.d/$svc" "/etc/xinetd.d/${svc}-tcp" "/etc/xinetd.d/${svc}-udp"; do
            fix_xinetd_disable "$xf" && applied="$applied $xf"
        done
        if [ -f /etc/inetd.conf ] && grep -qE "^[[:space:]]*${svc}[[:space:]]" /etc/inetd.conf; then
            fix_backup /etc/inetd.conf
            sed -i -E "s/^([[:space:]]*${svc}[[:space:]].*)/#\1/" /etc/inetd.conf
            applied="$applied /etc/inetd.conf(${svc} 주석처리)"
        fi
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="echo/discard/daytime/chargen 관련 inetd/xinetd 설정을 찾지 못함(커널/다른 서비스가 직접 열었을 수 있어 수동 확인 필요)"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"
        FIX_DETAIL="DoS 취약 서비스(echo/discard/daytime/chargen)를 비활성화함:$applied"
        FIX_EVIDENCE="$applied"
    fi
}
