# U-36 (상) r 계열 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = r 계열(rlogin/rsh/rexec) 서비스가 비활성화된 경우
#                        취약 = 활성화된 경우
# 전 Unix 계열 공통 로직.

run_check() {
    check_service_disabled "r 계열(rlogin/rsh/rexec)" "in\.rlogind|in\.rshd|in\.rexecd|rlogind|rshd|rexecd" "rlogin.socket rsh.socket rexec.socket"

    if [ "$CHECK_STATUS" = "GOOD" ]; then
        for f in /etc/xinetd.d/rlogin /etc/xinetd.d/rsh /etc/xinetd.d/rexec /etc/xinetd.d/shell /etc/xinetd.d/login; do
            [ -f "$f" ] || continue
            if grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' "$f" 2>/dev/null; then
                CHECK_STATUS="VULN"
                CHECK_DETAIL="r 계열 서비스가 xinetd 를 통해 활성화되어 있음"
                CHECK_EVIDENCE="$f: disable = no"
                break
            fi
        done
    fi
}
