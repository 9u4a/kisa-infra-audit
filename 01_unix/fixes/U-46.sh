# U-46 (상) 일반 사용자의 메일 서비스 실행 방지 — 조치
run_fix() {
    applied=""

    f="/etc/mail/sendmail.cf"
    if [ -f "$f" ]; then
        line=$(grep -iE '^O[[:space:]]*PrivacyOptions' "$f" | tail -n1)
        if ! printf '%s' "$line" | grep -qi 'restrictqrun'; then
            fix_backup "$f"
            if [ -n "$line" ]; then
                sed -i -E "s/^(O[[:space:]]*PrivacyOptions[[:space:]]*=.*)/\1,restrictqrun/I" "$f"
            else
                printf 'O PrivacyOptions=restrictqrun\n' >> "$f"
            fi
            applied="$applied sendmail(restrictqrun 추가)"
        fi
    fi

    for bin in /usr/sbin/postsuper /usr/sbin/exiqgrep; do
        [ -x "$bin" ] || continue
        find "$bin" -perm -0001 2>/dev/null | grep -q . || continue
        fix_backup "$bin"
        chmod o-x "$bin" 2>/dev/null
        applied="$applied $bin(일반사용자 실행권한 제거)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="메일 서비스 미설치 또는 이미 제한되어 있어 조치 불필요"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="메일 큐 조작 제한 조치:$applied"; FIX_EVIDENCE="$applied"
    fi
}
