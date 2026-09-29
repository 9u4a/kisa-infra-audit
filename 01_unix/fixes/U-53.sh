# U-53 (하) FTP 서비스 정보 노출 제한 — 조치
run_fix() {
    applied=""

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        grep -qiE '^[[:space:]]*ftpd_banner' "$f" && continue
        fix_backup "$f"
        printf 'ftpd_banner=Authorized users only.\n' >> "$f"
        applied="$applied $f(ftpd_banner 설정)"
    done

    for f in /etc/proftpd.conf /etc/proftpd/proftpd.conf; do
        [ -f "$f" ] || continue
        fix_backup "$f"
        if grep -qiE '^[[:space:]]*ServerIdent' "$f"; then
            sed -i -E 's/^([[:space:]]*ServerIdent[[:space:]]+)on[[:space:]]*$/\1on "Authorized users only."/I' "$f"
        else
            printf 'ServerIdent on "Authorized users only."\n' >> "$f"
        fi
        applied="$applied $f(ServerIdent 커스텀 배너)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="FTP 미사용 또는 이미 배너가 설정되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="FTP 배너를 버전 비노출 문구로 설정함:$applied (서비스 재시작 후 적용)"; FIX_EVIDENCE="$applied"
    fi
}
