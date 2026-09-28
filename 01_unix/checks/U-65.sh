# U-65 (중) NTP 및 시각 동기화 설정
# 판단 기준(가이드 원문): 양호 = NTP/시각 동기화 설정이 기준에 따라 적용된 경우
#                        취약 = 적용되어 있지 않은 경우
# 자동화 범위: LINUX 기준 chrony/ntpd 서비스 활성 + 서버 설정 존재 여부.

run_check() {
    active=""
    servers=""

    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet chronyd 2>/dev/null && active="chronyd"
        [ -z "$active" ] && systemctl is-active --quiet chrony 2>/dev/null && active="chrony"
        [ -z "$active" ] && systemctl is-active --quiet ntpd 2>/dev/null && active="ntpd"
        [ -z "$active" ] && systemctl is-active --quiet ntp 2>/dev/null && active="ntp"
    fi

    for f in /etc/chrony.conf /etc/chrony/chrony.conf /etc/ntp.conf; do
        [ -f "$f" ] || continue
        s=$(grep -E '^[[:space:]]*(server|pool)[[:space:]]' "$f" 2>/dev/null)
        [ -n "$s" ] && servers="$servers
$f:
$s"
    done

    if [ -n "$active" ] && [ -n "$servers" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="시간 동기화 서비스(${active})가 활성화되어 있고 NTP 서버가 설정되어 있음"
    elif [ -n "$servers" ] && [ -z "$active" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="NTP 서버는 설정되어 있으나 동기화 서비스가 실행 중이지 않음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="NTP/시각 동기화 설정을 찾을 수 없음"
    fi
    CHECK_EVIDENCE="실행 중인 서비스: ${active:-없음}$servers"
}
