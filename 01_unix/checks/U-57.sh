# U-57 (중) Ftpusers 파일 설정
# 판단 기준(가이드 원문): 양호 = root 계정의 FTP 접속을 차단한 경우 / 취약 = 허용한 경우
# 자동화 범위: ftpusers(root 등록), vsftpd(user_list+userlist_deny=yes+root 등록),
#             proftpd(RootLogin off). FTP 미설치 시 GOOD.

run_check() {
    checked=0
    root_blocked=0
    evidence=""

    for f in /etc/ftpusers /etc/ftpd/ftpusers; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -E '^[[:space:]]*root[[:space:]]*$' "$f" 2>/dev/null)
        evidence="$evidence
$f 내 root 등록: $( [ -n "$line" ] && echo 예 || echo 아니오 )"
        [ -n "$line" ] && root_blocked=1
    done

    for f in /etc/vsftpd.user_list /etc/vsftpd/user_list; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -E '^[[:space:]]*root[[:space:]]*$' "$f" 2>/dev/null)
        evidence="$evidence
$f 내 root 등록: $( [ -n "$line" ] && echo 예 || echo 아니오 )"
        [ -n "$line" ] && root_blocked=1
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -iE '^[[:space:]]*RootLogin' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f: ${line:-RootLogin 미설정(기본값 off)}"
        printf '%s' "$line" | grep -qi 'on' || root_blocked=1
    done

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="FTP 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    elif [ "$root_blocked" -eq 1 ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="root 계정의 FTP 접속이 차단되어 있음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="root 계정의 FTP 접속 차단 설정을 확인하지 못함"
        CHECK_EVIDENCE="$evidence"
    fi
}
