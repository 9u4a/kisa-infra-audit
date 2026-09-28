# U-35 (상) 공유 서비스에 대한 익명 접근 제한 설정
# 판단 기준(가이드 원문): 양호 = 공유 서비스 익명 접근 제한(또는 공유 서비스 미사용) / 취약 = 허용
# 자동화 범위: vsftpd/proftpd(anonymous), NFS(/etc/exports anon 옵션), Samba(guest ok) 확인.

run_check() {
    checked=0
    violations=""
    evidence=""

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        line=$(grep -iE '^[[:space:]]*anonymous_enable' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f: ${line:-anonymous_enable 미설정(기본값 NO)}"
        printf '%s' "$line" | grep -qiE '=\s*yes' && violations="$violations vsftpd(anonymous_enable=YES)"
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        checked=1
        anon_block=$(sed -n '/<Anonymous/,/<\/Anonymous>/p' "$f" 2>/dev/null | grep -vE '^[[:space:]]*#')
        evidence="$evidence
$f: Anonymous 블록 $( [ -n "$anon_block" ] && echo '활성' || echo '없음/주석' )"
        [ -n "$anon_block" ] && violations="$violations proftpd(Anonymous 블록 활성)"
    done

    if [ -f /etc/exports ]; then
        checked=1
        anon=$(grep -E 'anonuid|anongid|anon=' /etc/exports 2>/dev/null)
        evidence="$evidence
/etc/exports anon 관련 설정: ${anon:-없음}"
        printf '%s' "$anon" | grep -qE 'anon=-1' || { [ -n "$anon" ] && violations="$violations NFS(anon 옵션 확인 필요)"; }
    fi

    for f in /etc/samba/smb.conf /usr/lib/smb.conf; do
        [ -f "$f" ] || continue
        checked=1
        guest=$(grep -iE '^[[:space:]]*guest ok' "$f" 2>/dev/null | tail -n1)
        evidence="$evidence
$f: ${guest:-guest ok 미설정(기본값 no)}"
        printf '%s' "$guest" | grep -qiE '=\s*yes' && violations="$violations Samba(guest ok=yes)"
    done

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="FTP/NFS/Samba 등 공유 서비스가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="설치된 공유 서비스에서 익명 접근이 허용되어 있지 않음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="익명 접근이 허용된 공유 서비스가 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}
