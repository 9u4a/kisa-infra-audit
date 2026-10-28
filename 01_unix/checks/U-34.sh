# U-34 (상) Finger 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = Finger 서비스 비활성화 / 취약 = 활성화
# 전 Unix 계열 공통 로직.

run_check() {
    # inetd(/etc/inetd.conf)·소켓 유닛으로 기동되는 서비스는 연결 전에는 프로세스가 없어 예전에는 GOOD 이었다(진단 검수 U-R6).
    check_service_disabled "Finger" "fingerd|in.fingerd" "finger.socket" "finger"
    if [ "$CHECK_STATUS" = "GOOD" ] && [ -f /etc/xinetd.d/finger ]; then
        if grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/finger 2>/dev/null; then
            CHECK_STATUS="VULN"
            CHECK_DETAIL="Finger 서비스가 활성화되어 있음"
            CHECK_EVIDENCE="/etc/xinetd.d/finger: disable = no"
        fi
    fi
}
