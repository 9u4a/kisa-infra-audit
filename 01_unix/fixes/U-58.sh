# U-58 (중) 불필요한 SNMP 서비스 구동 점검 — 조치
run_fix() {
    fix_service_disable snmpd
    pkill -f snmpd 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="SNMP 서비스(snmpd)를 정지/비활성화함(기반시설 시스템은 SNMP 사용 원칙적 금지)"
    FIX_EVIDENCE="systemctl disable snmpd"
}
