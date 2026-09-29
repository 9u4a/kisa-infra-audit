# U-59 (상) 안전한 SNMP 버전 사용 — 조치
# 가이드 조치 방법: SNMP v1/v2 대신 v3 사용. 자동화 범위: v3 계정을 대신 만들어주는 것은
# 비밀번호를 임의로 정해야 해 위험하므로, v1/v2 community 설정을 비활성화(주석 처리)한다.
run_fix() {
    conf=""
    for f in /etc/snmp/snmpd.conf /etc/net-snmp/snmp/snmpd.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="SNMP 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    if ! grep -qE '^[[:space:]]*(com2sec|rocommunity|rwcommunity)[[:space:]]' "$conf"; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="v1/v2 community 설정이 없어 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$conf"
    sed -i -E 's/^([[:space:]]*)(com2sec|rocommunity|rwcommunity)([[:space:]])/\1#\2\3/' "$conf"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$conf 의 SNMP v1/v2(com2sec/rocommunity/rwcommunity) 설정을 비활성화함(v3 전환 필요) — snmpd 재시작 후 적용"
    FIX_EVIDENCE="$(grep -E '(com2sec|rocommunity|rwcommunity)' "$conf")"
}
