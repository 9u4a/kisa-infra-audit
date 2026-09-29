# U-52 (중) Telnet 서비스 비활성화 — 조치
run_fix() {
    fix_service_disable telnet.socket
    fix_xinetd_disable /etc/xinetd.d/telnet
    pkill -f 'in\.telnetd|telnetd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Telnet 서비스를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable telnet.socket, xinetd disable=yes"
}
