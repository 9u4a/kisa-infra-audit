# PC-10 (상) 주기적 보안 패치 및 벤더 권고사항 적용
# 판단 기준(가이드 원문): 양호 = HOT FIX 설치 및 자동 업데이트 설정 + 내부 관리 절차 수립·이행
#                        취약 = 미설치 또는 절차 미수립
# "관리 절차 수립·이행 여부"는 운영 정책이라 자동 판정이 불가능하다. Windows Update 자동 설정과
# 최근 패치 이력을 근거로 제시하고 MANUAL 로 응답한다.

$auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$auOptions = Test-RegistryValue -Path $auPath -Name "AUOptions"
$noAuto = Test-RegistryValue -Path $auPath -Name "NoAutoUpdate"
$recentHotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5

$evidence = "AUOptions=$auOptions NoAutoUpdate=$noAuto`n최근 설치된 HotFix(최대 5개):`n" +
    (($recentHotfix | ForEach-Object { "$($_.HotFixID) $($_.InstalledOn)" }) -join "`n")

return New-CheckResult -Code "PC-10" -Status "MANUAL" `
    -Detail "패치 관리 절차 수립·이행 여부는 운영 정책 확인이 필요해 자동 판정할 수 없음. Windows Update 자동 설정과 최근 패치 이력을 근거로 수동 확인 필요" `
    -Evidence $evidence
