# U-53 (하) FTP 서비스 정보 노출 제한
# 판단 기준(가이드 원문): 양호 = FTP 접속 배너에 노출 정보 없음 / 취약 = 노출 정보 있음
# 자동화 범위: vsftpd(ftpd_banner), proftpd(ServerIdent). FTP 미사용 시 GOOD.

run_check() {
    checked=0
    violations=""
    evidence=""

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -iE '^[[:space:]]*ftpd_banner' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f: ${line:-ftpd_banner 미설정(기본 배너 노출 가능)}"
        [ -z "$line" ] && violations="$violations vsftpd(ftpd_banner 미설정)"
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -iE '^[[:space:]]*ServerIdent' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f: ${line:-ServerIdent 미설정(기본값 on, 버전 노출)}"
        if [ -z "$line" ]; then
            violations="$violations proftpd(ServerIdent 미설정)"
        elif printf '%s' "$line" | grep -qiE 'on[[:space:]]*$'; then
            violations="$violations proftpd(ServerIdent on, 커스텀 배너 미지정)"
        fi
    done

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="FTP 서비스(vsftpd/proftpd)가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="FTP 접속 배너에 버전 등 노출 정보가 없도록 설정되어 있음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="FTP 접속 배너 설정이 없거나 기본값이라 버전 정보가 노출될 수 있음:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}
