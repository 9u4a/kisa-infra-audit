# U-54 (중) 암호화되지 않는 FTP 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = 암호화되지 않은 FTP(vsftpd/proftpd 등) 비활성화 / 취약 = 활성화
# 전 Unix 계열 공통 로직. SFTP(SSH 기반)는 별도이므로 영향 없음.

run_check() {
    check_service_disabled "FTP(vsftpd/proftpd, 평문)" "vsftpd|proftpd|in\.ftpd" "vsftpd proftpd"

    if [ "$CHECK_STATUS" = "GOOD" ] && [ -f /etc/xinetd.d/ftp ]; then
        if grep -qE '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/ftp 2>/dev/null; then
            CHECK_STATUS="VULN"
            CHECK_DETAIL="FTP 서비스가 xinetd 를 통해 활성화되어 있음"
            CHECK_EVIDENCE="/etc/xinetd.d/ftp: disable = no"
        fi
    fi
}
