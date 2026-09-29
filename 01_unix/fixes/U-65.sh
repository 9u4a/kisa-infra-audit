# U-65 (중) NTP 및 시각 동기화 설정 — 조치
run_fix() {
    applied=""
    conf=""
    for f in /etc/chrony.conf /etc/chrony/chrony.conf /etc/ntp.conf; do
        [ -f "$f" ] && conf="$f" && break
    done

    if [ -n "$conf" ] && ! grep -qE '^[[:space:]]*(server|pool)[[:space:]]' "$conf"; then
        fix_backup "$conf"
        printf 'pool pool.ntp.org iburst\n' >> "$conf"
        applied="$applied $conf(pool.ntp.org 추가)"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        for svc in chronyd chrony ntpd ntp; do
            systemctl list-unit-files "$svc.service" >/dev/null 2>&1 || continue
            systemctl enable --now "$svc" 2>/dev/null && { applied="$applied ${svc}(시작/활성화)"; break; }
        done
    fi

    if [ -z "$applied" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="chrony/ntp 설정 파일 또는 systemd 유닛을 찾지 못해 자동 조치 불가(패키지 설치 필요 - 패키지 설치는 이 도구의 범위 밖)"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"
        FIX_DETAIL="시각 동기화 조치:$applied"
        FIX_EVIDENCE="$applied"
    fi
}
