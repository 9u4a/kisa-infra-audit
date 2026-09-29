# U-36 (상) r 계열 서비스 비활성화 — 조치
run_fix() {
    fix_service_disable rlogin.socket rsh.socket rexec.socket
    fix_xinetd_disable /etc/xinetd.d/rlogin /etc/xinetd.d/rsh /etc/xinetd.d/rexec /etc/xinetd.d/shell /etc/xinetd.d/login
    pkill -f 'in\.rlogind|in\.rshd|in\.rexecd|rlogind|rshd|rexecd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="r 계열(rlogin/rsh/rexec) 서비스를 정지/비활성화함"
    FIX_EVIDENCE="rlogin/rsh/rexec socket disable, 관련 xinetd disable=yes"
}
