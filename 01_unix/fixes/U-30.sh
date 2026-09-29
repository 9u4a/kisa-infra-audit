# U-30 (중) UMASK 설정 관리 — 조치
# 가이드 조치 방법: UMASK 값을 022 이상으로 설정
run_fix() {
    applied=""
    f="/etc/profile"
    if [ -f "$f" ]; then
        fix_backup "$f"
        if grep -qiE '^[[:space:]]*umask[[:space:]]+[0-7]+' "$f"; then
            sed -i -E 's/^([[:space:]]*)[Uu][Mm][Aa][Ss][Kk][[:space:]]+[0-7]+/\1umask 022/' "$f"
        else
            printf 'umask 022\n' >> "$f"
        fi
        applied="$applied $f"
    fi
    f="/etc/login.defs"
    if [ -f "$f" ]; then
        fix_backup "$f"
        if grep -qiE '^[[:space:]]*umask[[:space:]]+[0-7]+' "$f"; then
            sed -i -E 's/^([[:space:]]*)[Uu][Mm][Aa][Ss][Kk][[:space:]]+[0-7]+/\1UMASK 022/' "$f"
        else
            printf 'UMASK 022\n' >> "$f"
        fi
        applied="$applied $f"
    fi
    if [ -z "$applied" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="/etc/profile, /etc/login.defs 모두 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="UMASK 022 설정함:$applied"; FIX_EVIDENCE="$applied"
    fi
}
