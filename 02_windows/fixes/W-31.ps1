# W-31 (중) SNMP Access Control 설정 [fix: auto]
# W-29.ps1 참고 — 동일한 이유로 SNMP 서비스 자체를 중지한다.

Disable-FixService -Name "SNMP"
