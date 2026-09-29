# W-57 (하) 로그온 시 경고 메시지 설정 [fix: auto]
# checks/W-57.ps1: 양호 = 제목/내용이 모두 설정된 경우. 문구 자체는 조직마다 다를 수 있지만
# "설정되어 있다"는 판단 기준을 충족하는 일반적인 표준 경고문을 기본값으로 사용한다(추후
# 조직 정책에 맞게 재설정 가능한 일반 텍스트라 U-28류의 "값을 알 수 없는" 문제가 아니다).

$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-FixRegistryValue -Path $path -Name "LegalNoticeCaption" -Value "경고" -Type String
$d1 = $Global:FixDetail
Set-FixRegistryValue -Path $path -Name "LegalNoticeText" -Value "본 시스템은 인가된 사용자만 이용할 수 있습니다. 무단으로 접근하거나 이용할 경우 관련 법령에 따라 처벌받을 수 있습니다." -Type String
$Global:FixDetail = "$d1; $($Global:FixDetail)"
