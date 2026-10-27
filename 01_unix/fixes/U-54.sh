# U-54 (중) 암호화되지 않는 FTP 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
run_fix() {
    fix_service_disable vsftpd proftpd
    fix_xinetd_disable /etc/xinetd.d/ftp
    pkill -f 'vsftpd|proftpd|in\.ftpd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="평문 FTP 서비스(vsftpd/proftpd)를 정지/비활성화함(SFTP 사용 권장)"
    FIX_EVIDENCE="systemctl disable vsftpd proftpd, xinetd disable=yes"
}
