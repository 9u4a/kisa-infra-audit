# PC-15 (상) OS에서 제공하는 침입차단 기능 활성화 [fix: confirm — deviation 있음]
# 02_windows/fixes/W-64.ps1 과 동일한 이유(원격 관리 세션 lockout 위험)로 lib/Common.psm1
# Enable-FixFirewallSafely 를 쓴다(원격 관리 규칙은 리소스 ID 로, 허용 규칙이 없으면 켜지 않음).

Enable-FixFirewallSafely
