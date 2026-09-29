# U-61 (상) SNMP Access Control 설정 — 조치
# 자동화 범위: 관리자가 허용할 네트워크 대역을 알 수 없으므로, 접근 제어가 없는(전체 허용)
# 항목은 원격 접근을 완전히 열어두는 것보다 안전한 localhost(127.0.0.1) 로 좁힌다(필요 시
# 관리자가 실제 모니터링 서버 대역으로 재조정해야 함).
run_fix() {
    conf=""
    for f in /etc/snmp/snmpd.conf /etc/net-snmp/snmp/snmpd.conf; do
        [ -f "$f" ] && conf="$f"
    done
    if [ -z "$conf" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="SNMP 미사용으로 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    if ! grep -qE '^[[:space:]]*(com2sec|rocommunity|rwcommunity)[[:space:]]+\S+[[:space:]]+(default|0\.0\.0\.0/0|any)([[:space:]]|$)' "$conf"; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="이미 접근 제어가 설정되어 있거나 대상 라인이 없어 조치 불필요"; FIX_EVIDENCE=""
        return
    fi
    fix_backup "$conf"
    sed -i -E 's/^([[:space:]]*com2sec[[:space:]]+\S+[[:space:]]+)(default|0\.0\.0\.0\/0|any)([[:space:]])/\1localhost\3/' "$conf"
    sed -i -E 's/^([[:space:]]*r[ow]community[[:space:]]+\S+[[:space:]]+)(default|0\.0\.0\.0\/0|any)([[:space:]]|$)/\1127.0.0.1\3/' "$conf"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="$conf 의 무제한(default/0.0.0.0/0/any) SNMP 접근을 localhost 로 제한함(원격 모니터링이 필요하면 실제 서버 IP로 재조정 필요) — snmpd 재시작 후 적용"
    FIX_EVIDENCE="$(grep -E '(com2sec|r[ow]community)' "$conf")"
}
