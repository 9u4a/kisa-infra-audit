# U-44 (상) tftp, talk 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = tftp/talk/ntalk 서비스 비활성화 / 취약 = 활성화
# 전 Unix 계열 공통 로직.

run_check() {
    check_service_disabled "tftp/talk/ntalk" "tftpd|talkd|ntalkd" "tftp talk ntalk"

    if [ "$CHECK_STATUS" = "GOOD" ]; then
        for f in /etc/xinetd.d/tftp /etc/xinetd.d/talk /etc/xinetd.d/ntalk; do
            [ -f "$f" ] || continue
            if grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' "$f" 2>/dev/null; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="tftp/talk/ntalk 서비스가 xinetd 를 통해 활성화되어 있음"
                CHECK_EVIDENCE="$f: disable = no"
                break
            fi
        done
    fi
}
