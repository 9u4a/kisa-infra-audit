# U-47 (상) 스팸 메일 릴레이 제한 — 조치
run_fix() {
    applied=""

    if command -v postconf >/dev/null 2>&1; then
        relay=$(postconf -h smtpd_relay_restrictions 2>/dev/null)
        recipient=$(postconf -h smtpd_recipient_restrictions 2>/dev/null)
        if ! printf '%s %s' "$relay" "$recipient" | grep -q 'reject_unauth_destination'; then
            [ -f /etc/postfix/main.cf ] && fix_backup /etc/postfix/main.cf
            postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination" 2>/dev/null
            applied="$applied postfix(smtpd_recipient_restrictions에 reject_unauth_destination 추가)"
        fi
    fi

    for f in /etc/mail/sendmail.mc /etc/mail/sendmail.cf; do
        [ -f "$f" ] || continue
        grep -il 'promiscuous_relay' "$f" 2>/dev/null | grep -v '^#' | grep -q . || continue
        fix_backup "$f"
        sed -i -E '/promiscuous_relay/ s/^/#/I' "$f"
        applied="$applied $f(promiscuous_relay 비활성화)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="메일 서비스 미설치 또는 이미 릴레이 제한이 설정되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="스팸 릴레이 제한 조치:$applied (postfix는 reload 필요)"; FIX_EVIDENCE="$applied"
    fi
}
