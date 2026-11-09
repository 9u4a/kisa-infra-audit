# W-31 (중) SNMP Access Control 설정 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 변경: SNMP 서비스 중지 + 시작 유형 사용 안 함(SNMP 모니터링 중단)
# 영향: 실행 중인 SNMP 서비스 중지·사용 안 함 — SNMP 모니터링 중단
# W-29.ps1 참고 — 동일한 이유로 SNMP 서비스 자체를 중지한다.

Disable-FixService -Name "SNMP"
