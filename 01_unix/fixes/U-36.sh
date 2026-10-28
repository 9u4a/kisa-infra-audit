# U-36 (상) r 계열 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable rlogin.socket rsh.socket rexec.socket
    fix_xinetd_disable /etc/xinetd.d/rlogin /etc/xinetd.d/rsh /etc/xinetd.d/rexec /etc/xinetd.d/shell /etc/xinetd.d/login
    # check 가 /etc/inetd.conf 를 보게 되어(진단 검수 U-R6) 조치도 같은 항목을 주석 처리한다.
    fix_inetd_disable login shell exec
    pkill -f 'in\.rlogind|in\.rshd|in\.rexecd|rlogind|rshd|rexecd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="r 계열(rlogin/rsh/rexec) 서비스를 정지/비활성화함"
    FIX_EVIDENCE="rlogin/rsh/rexec socket disable, 관련 xinetd disable=yes"
}
