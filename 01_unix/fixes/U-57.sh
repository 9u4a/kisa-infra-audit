# U-57 (중) Ftpusers 파일 설정 — 조치
# 가이드 조치 방법: root 계정의 FTP 접속 차단
run_fix() {
    applied=""

    for f in /etc/ftpusers /etc/ftpd/ftpusers; do
        [ -f "$f" ] || continue
        grep -qE '^[[:space:]]*root[[:space:]]*$' "$f" || { fix_backup "$f"; printf 'root\n' >> "$f"; applied="$applied $f"; }
    done

    # check(U-57)와 같은 기준(진단 검수 U-R15): user_list 는 userlist_enable=YES·userlist_deny≠NO(차단 목록)일 때만
    # root 를 추가한다 - userlist_deny=NO(허용 목록)에 root 를 넣으면 오히려 root 접속을 허용하게 된다.
    _ul_en=""; _ul_deny=""
    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        _v=$(grep -iE '^[[:space:]]*userlist_enable[[:space:]]*=' "$f" | tail -n1 | sed -E 's/.*=[[:space:]]*//' | tr '[:lower:]' '[:upper:]')
        [ -n "$_v" ] && _ul_en=$_v
        _v=$(grep -iE '^[[:space:]]*userlist_deny[[:space:]]*=' "$f" | tail -n1 | sed -E 's/.*=[[:space:]]*//' | tr '[:lower:]' '[:upper:]')
        [ -n "$_v" ] && _ul_deny=$_v
    done
    if [ "$_ul_en" = "YES" ] && [ "$_ul_deny" != "NO" ]; then
        for f in /etc/vsftpd.user_list /etc/vsftpd/user_list; do
            [ -f "$f" ] || continue
            grep -qE '^[[:space:]]*root[[:space:]]*$' "$f" || { fix_backup "$f"; printf 'root\n' >> "$f"; applied="$applied $f"; }
        done
    fi

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        line=$(grep -iE '^[[:space:]]*RootLogin' "$f" | tail -n1)
        printf '%s' "$line" | grep -qi 'on' || continue
        fix_backup "$f"
        sed -i -E 's/^([[:space:]]*RootLogin[[:space:]]+)on/\1off/I' "$f"
        applied="$applied $f(RootLogin off)"
    done

    if [ -z "$applied" ]; then
        _has_ftp=0
        for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
            [ -f "$f" ] && _has_ftp=1
        done
        if [ "$_has_ftp" -eq 0 ]; then
            FIX_STATUS="APPLIED"; FIX_DETAIL="FTP 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        else
            FIX_STATUS="APPLIED"; FIX_DETAIL="root 계정이 이미 차단되어 있어 조치 불필요"; FIX_EVIDENCE=""
        fi
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="root 계정의 FTP 접속을 차단함:$applied"; FIX_EVIDENCE="$applied"
    fi
}
