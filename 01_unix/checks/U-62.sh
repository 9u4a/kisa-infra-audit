# U-62 (하) 로그인 시 경고 메시지 설정
# 판단 기준(가이드 원문): 양호 = 서버 및 사용 중인 Telnet/FTP/SMTP/DNS 서비스에 로그온 경고 메시지 설정
#                        취약 = 미설정
# 자동화 범위: 서버 콘솔(/etc/motd, /etc/issue) + SSH(Banner) 는 항상 확인, 그 외 서비스는
#             설치된 경우에만 확인.

run_check() {
    missing=""
    evidence=""

    for f in /etc/motd /etc/issue; do
        if [ -s "$f" ]; then
            evidence="$evidence
$f: 설정됨 (비어있지 않음)"
        else
            missing="$missing $f(없음/비어있음)"
        fi
    done

    if [ -f /etc/ssh/sshd_config ]; then
        line=$(grep -iE '^[[:space:]]*Banner[[:space:]]' /etc/ssh/sshd_config 2>/dev/null | grep -viE 'none' | tail -n1)
        evidence="$evidence
sshd_config Banner: ${line:-미설정}"
        [ -z "$line" ] && missing="$missing sshd(Banner 미설정)"
    fi

    if command -v in.telnetd >/dev/null 2>&1 || command -v telnetd >/dev/null 2>&1; then
        if [ -s /etc/issue.net ]; then
            evidence="$evidence
/etc/issue.net: 설정됨"
        else
            missing="$missing telnet(/etc/issue.net 없음/비어있음)"
        fi
    fi

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        line=$(grep -iE '^[[:space:]]*(ftpd_banner|banner_file)' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f banner: ${line:-미설정}"
        [ -z "$line" ] && missing="$missing vsftpd(배너 미설정)"
    done

    if command -v postconf >/dev/null 2>&1; then
        banner=$(postconf -h smtpd_banner 2>/dev/null)
        evidence="$evidence
postfix smtpd_banner: ${banner:-기본값}"
    fi

    if [ -z "$missing" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="서버 콘솔/SSH 및 설치된 서비스에 로그온 경고 메시지가 설정되어 있음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="로그온 경고 메시지가 설정되지 않은 항목이 있음:$missing"
    fi
    CHECK_EVIDENCE="$evidence"
}
