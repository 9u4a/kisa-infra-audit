# U-48 (중) expn, vrfy 명령어 제한 — 조치
run_fix() {
    applied=""

    f="/etc/mail/sendmail.cf"
    if [ -f "$f" ]; then
        line=$(grep -iE '^O[[:space:]]*PrivacyOptions' "$f" | tail -n1)
        ok=0
        printf '%s' "$line" | grep -qi 'goaway' && ok=1
        { printf '%s' "$line" | grep -qi 'novrfy' && printf '%s' "$line" | grep -qi 'noexpn'; } && ok=1
        if [ "$ok" -ne 1 ]; then
            fix_backup "$f"
            if [ -n "$line" ]; then
                sed -i -E "s/^(O[[:space:]]*PrivacyOptions[[:space:]]*=.*)/\1,noexpn,novrfy/I" "$f"
            else
                printf 'O PrivacyOptions=noexpn,novrfy\n' >> "$f"
            fi
            applied="$applied sendmail(noexpn,novrfy 추가)"
        fi
    fi

    if command -v postconf >/dev/null 2>&1; then
        vrfy=$(postconf -h disable_vrfy_command 2>/dev/null)
        if [ "$vrfy" != "yes" ]; then
            [ -f /etc/postfix/main.cf ] && fix_backup /etc/postfix/main.cf
            postconf -e "disable_vrfy_command = yes" 2>/dev/null
            applied="$applied postfix(disable_vrfy_command=yes)"
        fi
    fi

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="메일 서비스 미설치 또는 이미 제한되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="expn/vrfy 제한 조치:$applied"; FIX_EVIDENCE="$applied"
    fi
}
