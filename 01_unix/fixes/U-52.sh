# U-52 (중) Telnet 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable telnet.socket
    fix_xinetd_disable /etc/xinetd.d/telnet
    # check 가 /etc/inetd.conf 를 보게 되어(진단 검수 U-R6) 조치도 같은 항목을 주석 처리한다.
    fix_inetd_disable telnet
    pkill -f 'in\.telnetd|telnetd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="Telnet 서비스를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable telnet.socket, xinetd disable=yes"
}
