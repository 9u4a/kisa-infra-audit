# W-64 (중) 윈도우 방화벽 설정 [fix: confirm — deviation 있음]
# checks/W-64.ps1: 양호 = 모든 방화벽 프로필(도메인/개인/공용)이 사용으로 설정된 경우.
#
# 방화벽을 켜는 행위 자체가 원격 관리 세션(RDP/WinRM)이나 업무 포트를 차단할 수 있어(U-28과 같은 계열의
# lockout 위험 — guide.json deviation 참고) lib/Common.psm1 Enable-FixFirewallSafely 로 켠다:
# 사용 중인 원격 관리 규칙만 리소스 ID 로 켜고, RDP·WinRM 포트 허용 규칙이 확인되지 않으면 켜지 않는다.
# 이 서버의 업무 포트(웹·DB 등) 허용 규칙은 스크립트가 알 수 없으므로 confirm 단계에서 사람이 확인한다.

Enable-FixFirewallSafely -Note " - 업무 서비스 포트(웹·DB 등)의 허용 규칙은 별도로 확인 필요"
