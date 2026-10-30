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
            # U-C3(1.4.0): 조치 전 상태를 기록하고 켠다(lib/common.sh fix_service_enable) - 예전에는 원복해도 켜진 채로 남았다
            fix_service_enable "$svc.service" && { applied="$applied ${svc}(시작/활성화)"; break; }
        done
    fi

    if [ -z "$applied" ]; then
        # 아무것도 바꾸지 않았으므로 SKIPPED(fix.sh 가 재검증·원복 없이 사유만 기록)
        FIX_STATUS="SKIPPED"
        FIX_DETAIL="변경 없음 - chrony/ntp 설정 파일 또는 systemd 유닛을 찾지 못해 자동 조치 불가(패키지 설치 필요 - 패키지 설치는 이 도구의 범위 밖)"
        FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"
        FIX_DETAIL="시각 동기화 조치:$applied"
        FIX_EVIDENCE="$applied"
    fi
}
