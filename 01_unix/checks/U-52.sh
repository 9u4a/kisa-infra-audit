# U-52 (중) Telnet 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = Telnet 비활성화 / 취약 = 사용 중
# 전 Unix 계열 공통 로직.

run_check() {
    # inetd(/etc/inetd.conf)·소켓 유닛으로 기동되는 서비스는 연결 전에는 프로세스가 없어 예전에는 GOOD 이었다(진단 검수 U-R6).
    check_service_disabled "Telnet" "in\.telnetd|telnetd" "telnet.socket" "telnet"

    if [ "$CHECK_STATUS" = "GOOD" ] && [ -f /etc/xinetd.d/telnet ]; then
        if grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/telnet 2>/dev/null; then
            CHECK_STATUS="VULN"
            CHECK_DETAIL="Telnet 서비스가 xinetd 를 통해 활성화되어 있음"
            CHECK_EVIDENCE="/etc/xinetd.d/telnet: disable = no"
        fi
    fi
}
