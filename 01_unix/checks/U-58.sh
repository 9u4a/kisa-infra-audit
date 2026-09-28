# U-58 (중) 불필요한 SNMP 서비스 구동 점검
# 판단 기준(가이드 원문): 양호 = SNMP 서비스를 사용하지 않는 경우 / 취약 = 사용하는 경우
# 전 Unix 계열 공통 로직 (기반시설 시스템은 SNMP 사용이 원칙적으로 금지됨).

run_check() {
    check_service_disabled "SNMP" "snmpd" "snmpd"
}
