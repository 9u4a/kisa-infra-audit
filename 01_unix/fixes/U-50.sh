# U-50 (상) DNS ZoneTransfer 설정 — 조치
# 자동화 범위: 관리자가 허용할 대상을 알 수 없으므로 전체 허용을 "허용 없음(none)"으로
# 안전하게 좁힌다(필요 시 관리자가 실제 보조 네임서버 IP로 다시 넓혀야 함).
run_fix() {
    conf=""
    for f in /etc/named.conf /etc/bind/named.conf.options /etc/bind/named.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="DNS(BIND) 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$conf"
    if grep -qiE 'allow-transfer' "$conf"; then
        sed -i -E 's/allow-transfer[[:space:]]*\{[^}]*\}[[:space:]]*;/allow-transfer { none; };/I' "$conf"
    else
        sed -i -E '0,/options[[:space:]]*\{/{s/options[[:space:]]*\{/options {\n\tallow-transfer { none; };/}' "$conf"
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$conf 의 allow-transfer 를 none 으로 제한함(필요 시 실제 보조 네임서버 IP로 재조정 필요) — named 재시작 후 적용"
    FIX_EVIDENCE="$(grep -i allow-transfer "$conf")"
}
