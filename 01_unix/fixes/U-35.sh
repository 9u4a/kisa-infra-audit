# U-35 (상) 공유 서비스에 대한 익명 접근 제한 설정 — 조치
run_fix() {
    applied=""

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        grep -qiE '^[[:space:]]*anonymous_enable[[:space:]]*=[[:space:]]*yes' "$f" || continue
        fix_backup "$f"
        fix_sed_inplace "$f" -E 's/^([[:space:]]*)anonymous_enable[[:space:]]*=[[:space:]]*yes/\1anonymous_enable=NO/I'
        applied="$applied $f(anonymous_enable=NO)"
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        grep -q '<Anonymous' "$f" 2>/dev/null || continue
        fix_backup "$f"
        fix_sed_inplace "$f" -E '/<Anonymous/,/<\/Anonymous>/ { /^[[:space:]]*#/! s/^/#/ }'
        applied="$applied $f(Anonymous 블록 주석 처리)"
    done

    for f in /etc/samba/smb.conf /usr/lib/smb.conf; do
        [ -f "$f" ] || continue
        # check(U-35)와 같은 기준(진단 검수 U-R15): 모든 섹션의 guest ok/public = yes|true|1
        grep -qiE '^[[:space:]]*(guest[[:space:]]*ok|public)[[:space:]]*=[[:space:]]*(yes|true|1)[[:space:]]*$' "$f" || continue
        fix_backup "$f"
        fix_sed_inplace "$f" -E 's/^([[:space:]]*)(guest[[:space:]]*ok|public)[[:space:]]*=[[:space:]]*(yes|true|1)[[:space:]]*$/\1\2 = no/I'
        applied="$applied $f(guest ok=no)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="자동 조치 가능한 vsftpd/proftpd/Samba 익명 접근 설정을 찾지 못함(NFS anon 옵션 등은 수동 확인 필요)"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"
        FIX_DETAIL="익명 접근을 차단함:$applied (서비스 재시작 후 적용)"
        FIX_EVIDENCE="$applied"
    fi
}
