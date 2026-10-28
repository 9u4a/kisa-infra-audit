# U-65 (중) NTP 및 시각 동기화 설정
# 판단 기준(가이드 원문): 양호 = NTP/시각 동기화 설정이 기준에 따라 적용된 경우
#                        취약 = 적용되어 있지 않은 경우
# 자동화 범위: LINUX 기준 chrony/ntpd 서비스 활성 + 서버 설정 존재 여부.

run_check() {
    active=""
    servers=""

    timesyncd=0
    if command -v systemctl >/dev/null 2>&1; then
        run_to 10 systemctl is-active --quiet chronyd 2>/dev/null && active="chronyd"
        [ -z "$active" ] && run_to 10 systemctl is-active --quiet chrony 2>/dev/null && active="chrony"
        [ -z "$active" ] && run_to 10 systemctl is-active --quiet ntpd 2>/dev/null && active="ntpd"
        [ -z "$active" ] && run_to 10 systemctl is-active --quiet ntp 2>/dev/null && active="ntp"
        [ -z "$active" ] && run_to 10 systemctl is-active --quiet ntpsec 2>/dev/null && active="ntpsec"
        # 진단 검수 U-R17: Debian/Ubuntu 기본 systemd-timesyncd 를 인식하지 못해 거짓 VULN 이었다.
        [ -z "$active" ] && run_to 10 systemctl is-active --quiet systemd-timesyncd 2>/dev/null && { active="systemd-timesyncd"; timesyncd=1; }
    fi

    for f in /etc/chrony.conf /etc/chrony/chrony.conf /etc/ntp.conf /etc/ntpsec/ntp.conf /etc/chrony/sources.d/*.sources /etc/chrony/conf.d/*.conf; do
        [ -f "$f" ] || continue
        s=$(grep -E '^[[:space:]]*(server|pool)[[:space:]]' "$f" 2>/dev/null)
        [ -n "$s" ] && servers="$servers
$f:
$s"
    done
    # timesyncd: [Time] 의 NTP= 가 명시 서버. 비어 있으면 빌드 기본 FallbackNTP(배포판 공용 풀)만 쓴다.
    ts_explicit=""
    if [ "$timesyncd" -eq 1 ]; then
        for f in /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.d/*.conf; do
            [ -f "$f" ] || continue
            s=$(grep -E '^[[:space:]]*(NTP|FallbackNTP)=[^[:space:]]' "$f" 2>/dev/null)
            [ -n "$s" ] && servers="$servers
$f:
$s"
            printf '%s\n' "$s" | grep -qE '^[[:space:]]*NTP=' && ts_explicit=1
        done
    fi

    if [ "$timesyncd" -eq 1 ] && [ -z "$ts_explicit" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="systemd-timesyncd 가 실행 중이나 NTP= 서버를 지정하지 않아 빌드 기본 FallbackNTP(배포판 공용 풀)를 사용 - 조직 기준 NTP 서버인지 확인 필요"
    elif [ -n "$active" ] && [ -n "$servers" ]; then
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
