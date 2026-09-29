# U-51 (중) DNS 서비스의 취약한 동적 업데이트 설정 금지 — 조치
run_fix() {
    conf=""
    for f in /etc/named.conf /etc/bind/named.conf.options /etc/bind/named.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="DNS(BIND) 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    if ! grep -qiE 'allow-update[[:space:]]*\{[^}]*any[[:space:]]*;' "$conf"; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="allow-update 가 이미 any(전체 허용)가 아니어서 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$conf"
    sed -i -E 's/allow-update[[:space:]]*\{[^}]*\}[[:space:]]*;/allow-update { none; };/I' "$conf"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$conf 의 allow-update 를 none 으로 제한함(동적 업데이트 비활성화) — named 재시작 후 적용"
    FIX_EVIDENCE="$(grep -i allow-update "$conf")"
}
