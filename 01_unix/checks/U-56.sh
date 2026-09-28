# U-56 (하) FTP 서비스 접근 제어 설정
# 판단 기준(가이드 원문): 양호 = 특정 IP/호스트만 접속 가능하도록 접근 제어 설정 적용
#                        취약 = 접근 제어 미설정
# 자동화 범위: vsftpd(userlist/tcp_wrappers), proftpd(Limit LOGIN), ftpusers 파일.
# FTP 미사용 시 GOOD.

run_check() {
    checked=0
    violations=""
    evidence=""

    for f in /etc/ftpusers /etc/ftpd/ftpusers; do
        [ -f "$f" ] || continue
        checked=1
        n=$(grep -vcE '^[[:space:]]*(#|$)' "$f" 2>/dev/null)
        evidence="$evidence
$f: 등록된 사용자 수 $n"
    done

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        ul=$(grep -iE '^[[:space:]]*userlist_enable' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f: ${ul:-userlist_enable 미설정}"
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        limit=$(sed -n '/<Limit LOGIN>/,/<\/Limit>/p' "$f" 2>/dev/null)
        evidence="$evidence
$f Limit LOGIN 블록: $( [ -n "$limit" ] && echo '있음' || echo '없음' )"
        [ -z "$limit" ] && violations="$violations proftpd(Limit LOGIN 없음)"
    done

    # 방화벽/TCP Wrapper 기반 접근 제어는 U-28 에서 종합 판정하므로 여기서는 다루지 않음.

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="FTP 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
        return
    fi

    if [ -z "$violations" ] && printf '%s' "$evidence" | grep -q "등록된 사용자 수 [1-9]"; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="ftpusers 등으로 FTP 접근 제어가 설정되어 있음"
    elif [ -z "$violations" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="FTP 서비스는 설치되어 있으나 접근 제어(ftpusers/Limit LOGIN 등) 설정 여부를 자동으로 단정하기 어려움 — 수동 확인 필요"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="FTP 접근 제어 설정이 확인되지 않음:$violations"
    fi
    CHECK_EVIDENCE="$evidence"
}
