# U-58 (중) 불필요한 SNMP 서비스 구동 점검 — 조치
# 변경: snmpd 서비스 정지·비활성화, snmpd 프로세스 종료
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
# 영향: 실행 중인 snmpd 중지·프로세스 종료 — SNMP 모니터링 수집 끊김
run_fix() {
    fix_service_disable snmpd
    fix_kill_procs snmpd
    FIX_STATUS="APPLIED"
    FIX_DETAIL="SNMP 서비스(snmpd)를 정지/비활성화함(기반시설 시스템은 SNMP 사용 원칙적 금지)"
    FIX_EVIDENCE="systemctl disable snmpd"
}
