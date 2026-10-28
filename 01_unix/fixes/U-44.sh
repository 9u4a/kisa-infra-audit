# U-44 (상) tftp, talk 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable tftp tftp.socket talk ntalk
    fix_xinetd_disable /etc/xinetd.d/tftp /etc/xinetd.d/talk /etc/xinetd.d/ntalk
    # check 가 /etc/inetd.conf 를 보게 되어(진단 검수 U-R6) 조치도 같은 항목을 주석 처리한다.
    fix_inetd_disable tftp talk ntalk
    pkill -f 'tftpd|talkd|ntalkd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="tftp/talk/ntalk 서비스를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable tftp talk ntalk, xinetd disable=yes"
}
