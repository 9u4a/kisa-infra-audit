# U-56 (하) FTP 서비스 접근 제어 설정
# 판단 기준(가이드 원문): 양호 = 특정 IP/호스트만 접속 가능하도록 접근 제어 설정 적용
#                        취약 = 접근 제어 미설정
# 자동화 범위: vsftpd(userlist/tcp_wrappers), proftpd(Limit LOGIN), ftpusers 파일.
# FTP 미사용 시 GOOD.

# 진단 검수 U-R15: ftpusers 는 "접속을 거부할 계정" 목록이지 IP/호스트 접근 제어가 아니다 - 예전에는 ftpusers 에
# 계정이 있으면 GOOD 이었다. 이제 IP 기반 접근 제어만 인정한다: vsftpd tcp_wrappers=YES(마지막 값이 적용) +
# hosts.allow/deny 의 vsftpd·ALL 규칙, proftpd <Limit LOGIN> 안의 Allow/Deny from. 방화벽은 U-28 에서 판정하므로
# 여기서 IP 제어를 찾지 못하면 VULN 이 아니라 MANUAL(방화벽 등 확인 필요)로 둔다(proftpd Limit LOGIN 부재는 기존대로 VULN).
run_check() {
    checked=0
    violations=""
    evidence=""
    ip_ctl=0

    for f in /etc/ftpusers /etc/ftpd/ftpusers; do
        [ -f "$f" ] || continue
        checked=1
        n=$(grep -vcE '^[[:space:]]*(#|$)' "$f" 2>/dev/null)
        evidence="$evidence
$f: 등록된(접속 거부) 사용자 수 $n - 계정 제한이며 IP 접근 제어는 아님"
    done

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        tw=$(grep -iE '^[[:space:]]*tcp_wrappers[[:space:]]*=' "$f" 2>/dev/null | tail -n1)
        rules=$(grep -hiE '^[[:space:]]*(vsftpd|ALL)[[:space:]]*(,[^:]*)?:' /etc/hosts.allow /etc/hosts.deny 2>/dev/null | head -n 5)
        evidence="$evidence
$f: ${tw:-tcp_wrappers 미설정(기본값 NO)}
hosts.allow/deny vsftpd·ALL 규칙: ${rules:-없음}"
        if printf '%s' "$tw" | grep -qiE '=[[:space:]]*yes' && [ -n "$rules" ]; then
            ip_ctl=1
        fi
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        limit=$(sed -n '/<Limit LOGIN>/,/<\/Limit>/p' "$f" 2>/dev/null | grep -vE '^[[:space:]]*#')
        evidence="$evidence
$f Limit LOGIN 블록: $( [ -n "$limit" ] && echo '있음' || echo '없음' )"
        if [ -z "$limit" ]; then
            violations="$violations proftpd(Limit LOGIN 없음)"
        elif printf '%s\n' "$limit" | grep -qiE '^[[:space:]]*(Allow|Deny)[[:space:]]+from'; then
            ip_ctl=1
        fi
    done

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="FTP 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
        return
    fi

    if [ -n "$violations" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="FTP 접근 제어 설정이 확인되지 않음:$violations"
    elif [ "$ip_ctl" -eq 1 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="FTP 서비스에 IP/호스트 기반 접근 제어(tcp_wrappers 또는 Limit LOGIN Allow/Deny)가 설정되어 있음"
    else
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="FTP 서비스 자체의 IP/호스트 접근 제어를 찾지 못함(ftpusers 는 계정 제한) — 방화벽(U-28) 등으로 제한하는지 수동 확인 필요"
    fi
    CHECK_EVIDENCE="$evidence"
}
