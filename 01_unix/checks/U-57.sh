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

    # 진단 검수 U-R15: vsftpd user_list 는 userlist_enable=YES 일 때만 쓰이고, userlist_deny=NO 면 "허용 목록"이라
    # root 가 들어 있으면 오히려 root 접속을 허용한다 - 예전에는 등록만 보고 차단으로 셌다. vsftpd 는 같은 키가
    # 여럿이면 마지막 값이 적용된다(기본값 userlist_enable=NO, userlist_deny=YES).
    ul_en=""; ul_deny=""
    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        v=$(grep -iE '^[[:space:]]*userlist_enable[[:space:]]*=' "$f" 2>/dev/null | tail -n1 | sed -E 's/.*=[[:space:]]*//' | tr '[:lower:]' '[:upper:]')
        [ -n "$v" ] && ul_en=$v
        v=$(grep -iE '^[[:space:]]*userlist_deny[[:space:]]*=' "$f" 2>/dev/null | tail -n1 | sed -E 's/.*=[[:space:]]*//' | tr '[:lower:]' '[:upper:]')
        [ -n "$v" ] && ul_deny=$v
    done
    for f in /etc/vsftpd.user_list /etc/vsftpd/user_list; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -E '^[[:space:]]*root[[:space:]]*$' "$f" 2>/dev/null)
        evidence="$evidence
$f 내 root 등록: $( [ -n "$line" ] && echo 예 || echo 아니오 ) (userlist_enable=${ul_en:-NO(기본값)}, userlist_deny=${ul_deny:-YES(기본값)})"
        if [ -n "$line" ] && [ "$ul_en" = "YES" ] && [ "$ul_deny" != "NO" ]; then
            root_blocked=1
        elif [ -z "$line" ] && [ "$ul_en" = "YES" ] && [ "$ul_deny" = "NO" ]; then
            # 허용 목록 방식에서 root 가 목록에 없으면 차단된 것
            root_blocked=1
        fi
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
