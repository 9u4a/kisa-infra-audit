# U-34 (상) Finger 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = Finger 서비스 비활성화 / 취약 = 활성화
# 전 Unix 계열 공통 로직.

run_check() {
    check_service_disabled "Finger" "fingerd|in.fingerd"
    if [ "$CHECK_STATUS" = "GOOD" ] && [ -f /etc/xinetd.d/finger ]; then
        if grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/finger 2>/dev/null; then
            CHECK_STATUS="VULN"
            CHECK_DETAIL="Finger 서비스가 활성화되어 있음"
            CHECK_EVIDENCE="/etc/xinetd.d/finger: disable = no"
        fi
    fi
}
