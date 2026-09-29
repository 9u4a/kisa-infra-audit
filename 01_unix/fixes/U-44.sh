# U-44 (상) tftp, talk 서비스 비활성화 — 조치
run_fix() {
    fix_service_disable tftp talk ntalk
    fix_xinetd_disable /etc/xinetd.d/tftp /etc/xinetd.d/talk /etc/xinetd.d/ntalk
    pkill -f 'tftpd|talkd|ntalkd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="tftp/talk/ntalk 서비스를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable tftp talk ntalk, xinetd disable=yes"
}
