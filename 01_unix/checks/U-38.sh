# U-38 (상) DoS 공격에 취약한 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = echo/discard/daytime/chargen 등 서비스가 비활성화된 경우
#                        취약 = 활성화된 경우
# 전 Unix 계열 공통 로직: 대상 포트가 실제로 리스닝 중인지 확인 (inetd/xinetd 대체 포함).

run_check() {
    targets="echo discard daytime chargen"
    listening=""

    if command -v ss >/dev/null 2>&1; then
        listen_out=$(ss -ltnu 2>/dev/null)
    elif command -v netstat >/dev/null 2>&1; then
        listen_out=$(netstat -ltnu 2>/dev/null)
    else
        listen_out=""
    fi

    for port in 7 9 13 19; do
        if printf '%s' "$listen_out" | grep -qE "[:.]${port}[[:space:]]"; then
            listening="$listening port:$port"
        fi
    done

    for svc in $targets; do
        for xf in /etc/xinetd.d/$svc /etc/xinetd.d/${svc}-tcp /etc/xinetd.d/${svc}-udp; do
            [ -f "$xf" ] || continue
            grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' "$xf" 2>/dev/null && listening="$listening xinetd:$svc"
        done
        grep -qE "^[[:space:]]*${svc}[[:space:]]" /etc/inetd.conf 2>/dev/null && listening="$listening inetd:$svc"
    done

    if [ -z "$listen_out" ] && [ -z "$listening" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="ss/netstat 명령을 사용할 수 없어 포트 리스닝 여부를 확인하지 못함. inetd/xinetd 설정에서는 활성 항목을 찾지 못함"
        CHECK_EVIDENCE=""
    elif [ -n "$listening" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="DoS 공격에 취약한 서비스(echo/discard/daytime/chargen)가 활성화되어 있음"
        CHECK_EVIDENCE="$listening"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="echo/discard/daytime/chargen 관련 포트(7/9/13/19)가 리스닝 중이지 않고 inetd/xinetd 설정도 비활성화됨"
        CHECK_EVIDENCE=""
    fi
}
