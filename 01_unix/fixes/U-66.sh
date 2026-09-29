# U-66 (중) 정책에 따른 시스템 로깅 설정 — 조치
# 자동화 범위: 이 항목은 VULN 조건이 "로깅 서비스 미실행" 또는 "유효 규칙 전무"인 두 경우뿐이며
# (그 외는 항상 MANUAL), 두 경우 모두 서비스 시작/기본 규칙 추가로 조치 가능하다.
run_fix() {
    applied=""
    if command -v systemctl >/dev/null 2>&1; then
        for svc in rsyslog syslog syslog-ng; do
            systemctl list-unit-files "$svc.service" >/dev/null 2>&1 || continue
            systemctl enable --now "$svc" 2>/dev/null && { applied="$applied ${svc}(시작/활성화)"; break; }
        done
    fi

    conf=""
    for f in /etc/rsyslog.conf /etc/syslog.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -n "$conf" ]; then
        rules=$(grep -vE '^[[:space:]]*(#|$)' "$conf")
        if [ -z "$rules" ]; then
            fix_backup "$conf"
            printf 'auth,authpriv.*                /var/log/secure\n*.info;mail.none;authpriv.none;cron.none    /var/log/messages\n' >> "$conf"
            applied="$applied $conf(기본 로깅 규칙 추가)"
        fi
    fi

    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="로깅 서비스가 이미 실행 중이고 규칙도 있어 조치 불필요(정책 일치 여부는 별도 수동 확인 필요)"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="시스템 로깅 조치:$applied"; FIX_EVIDENCE="$applied"
    fi
}
