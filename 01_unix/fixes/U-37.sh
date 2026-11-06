# U-37 (상) crontab 설정파일 권한 설정 미흡 — 조치
# 변경: /usr/bin/crontab·at 권한 750(750 초과·SUID 시), 기준을 넘는 cron/at 관련 파일(작업 목록 스풀, /etc/crontab,
#       /etc/cron.d/*, cron·at 의 allow/deny)에서 기준(640, at 작업 목록은 740) 밖의 비트만 제거
# check(U-37)와 같은 대상·기준(1.5.0 A1 - 예전에는 스풀의 기타 rwx 가 "모두" 있는 파일만, /etc/crontab·cron.d 미조치).
# 소유자는 바꾸지 않는다: 사용자 crontab 스풀 파일은 해당 사용자 소유여야 cron 이 읽는다.
run_fix() {
    applied=""

    for bin in /usr/bin/crontab /usr/bin/at; do
        [ -e "$bin" ] || continue
        perm=$(stat -L -c '%a' "$bin" 2>/dev/null)
        if [ -n "$perm" ] && perm_exceeds "$perm" 750; then
            fix_backup "$bin"
            chmod 750 "$bin" 2>/dev/null
            applied="$applied $bin(750)"
        fi
    done

    # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 으로 목록을 만든다
    list=""
    for d in /var/spool/cron /var/spool/cron/crontabs /var/spool/at /var/spool/cron/atjobs /etc/cron.d; do
        [ -d "$d" ] || continue
        lim=640
        case "$d" in /var/spool/at|/var/spool/cron/atjobs) lim=740 ;; esac
        list="$list
$(find "$d" -maxdepth 1 -type f 2>/dev/null | sed "s/^/$lim /")"
    done
    for f in /etc/crontab /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
        [ -f "$f" ] && list="$list
640 $f"
    done
    while read -r lim f; do
        [ -n "$f" ] || continue
        perm=$(stat -L -c '%a' "$f" 2>/dev/null)
        [ -n "$perm" ] && perm_exceeds "$perm" "$lim" || continue
        new=$(printf '%o' $(( 0$perm & 0$lim )))
        fix_backup "$f"
        chmod "$new" "$f" 2>/dev/null
        applied="$applied $f($perm->$new)"
    done <<EOF
$list
EOF

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 cron/at 파일이 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="cron/at 관련 파일 권한을 조치함:$applied"; FIX_EVIDENCE="$applied"
    fi
}
