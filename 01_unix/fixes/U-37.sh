# U-37 (상) crontab 설정파일 권한 설정 미흡 — 조치
run_fix() {
    applied=""

    for bin in /usr/bin/crontab /usr/bin/at; do
        [ -e "$bin" ] || continue
        perm=$(stat -L -c '%a' "$bin" 2>/dev/null)
        suid=$(find "$bin" -perm -4000 2>/dev/null)
        if { [ -n "$perm" ] && [ "$perm" -gt 750 ] 2>/dev/null; } || [ -n "$suid" ]; then
            fix_backup "$bin"
            chmod 750 "$bin" 2>/dev/null
            applied="$applied $bin(750)"
        fi
    done

    for d in /var/spool/cron /var/spool/cron/crontabs /var/spool/at /var/spool/cron/atjobs; do
        [ -d "$d" ] || continue
        bad=$(find "$d" -maxdepth 1 -type f -perm -0007 2>/dev/null)
        [ -z "$bad" ] && continue
        printf '%s\n' "$bad" | while IFS= read -r f; do
            [ -z "$f" ] && continue
            fix_backup "$f"
            chmod o-rwx "$f" 2>/dev/null
        done
        applied="$applied $d(other권한제거)"
    done

    for f in /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
        [ -f "$f" ] || continue
        perm=$(stat -L -c '%a' "$f" 2>/dev/null)
        [ -n "$perm" ] && [ "$perm" -gt 640 ] 2>/dev/null || continue
        fix_backup "$f"
        chmod 640 "$f" 2>/dev/null
        applied="$applied $f(640)"
    done

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 cron/at 파일이 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="cron/at 관련 파일 권한을 조치함:$applied"; FIX_EVIDENCE="$applied"
    fi
}
