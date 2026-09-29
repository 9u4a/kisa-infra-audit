# W-29 (중) 불필요한 SNMP 서비스 구동 점검 [fix: confirm]
# checks/W-29.ps1: 취약 = SNMP 구동 중이며 Community String 미설정.
# 특정 Community 문자열 값을 스크립트가 임의로 만들어 넣는 것보다(W-30 의 "복잡성" 요구까지
# 동시에 충족해야 함) 가이드의 첫 번째 대안인 "불필요 시 서비스 중지"가 더 안전한 자동화
# 대상이라고 판단해 SNMP 서비스 자체를 중지+비활성화한다(W-30/W-31 과 동일한 조치 - 세
# 항목 모두 "SNMP 서비스 중지"로 함께 해소됨). 실제로 SNMP 모니터링이 필요하면 사람이
# confirm 단계에서 거부하고 수동으로 Community/접근 제어를 구성해야 한다.

Disable-FixService -Name "SNMP"
