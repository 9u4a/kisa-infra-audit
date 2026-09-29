# U-62 (하) 로그인 시 경고 메시지 설정 — 조치
run_fix() {
    banner_text="Authorized access only. All activity may be monitored and reported."
    applied=""

    for f in /etc/motd /etc/issue; do
        [ -s "$f" ] && continue
        fix_backup "$f"
        printf '%s\n' "$banner_text" > "$f"
        applied="$applied $f"
    done

    if [ -f /etc/ssh/sshd_config ]; then
        line=$(grep -iE '^[[:space:]]*Banner[[:space:]]' /etc/ssh/sshd_config | grep -viE 'none' | tail -n1)
        if [ -z "$line" ]; then
            fix_backup /etc/ssh/sshd_config
            printf '%s\n' "$banner_text" > /etc/issue.net
            if grep -qiE '^[[:space:]]*Banner[[:space:]]' /etc/ssh/sshd_config; then
                sed -i -E 's#^([[:space:]]*Banner[[:space:]]+).*#\1/etc/issue.net#I' /etc/ssh/sshd_config
            else
                printf 'Banner /etc/issue.net\n' >> /etc/ssh/sshd_config
            fi
            applied="$applied sshd_config(Banner /etc/issue.net)"
        fi
    fi

    if command -v telnetd >/dev/null 2>&1 || command -v in.telnetd >/dev/null 2>&1; then
        if [ ! -s /etc/issue.net ]; then
            fix_backup /etc/issue.net
            printf '%s\n' "$banner_text" > /etc/issue.net
            applied="$applied /etc/issue.net"
        fi
    fi

    for f in /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf; do
        [ -f "$f" ] || continue
        grep -qiE '^[[:space:]]*(ftpd_banner|banner_file)' "$f" && continue
        fix_backup "$f"
        printf 'ftpd_banner=%s\n' "$banner_text" >> "$f"
        applied="$applied $f(ftpd_banner)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="모든 대상에 이미 경고 메시지가 설정되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="로그온 경고 메시지를 설정함:$applied (sshd/vsftpd 는 재시작 후 적용)"; FIX_EVIDENCE="$applied"
    fi
}
