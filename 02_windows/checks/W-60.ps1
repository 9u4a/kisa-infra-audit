# W-60 (중) 보안 채널 데이터 디지털 암호화 또는 서명
# 판단 기준(가이드 원문): 양호 = 아래 3개 정책이 모두 "사용" / 취약 = 하나라도 "사용 안 함"
#   RequireSignOrSeal(항상), SealSecureChannel(가능한 경우 암호화), SignSecureChannel(가능한 경우 서명)
# 도메인 구성원에게만 해당하는 정책이므로, 워크그룹(비도메인) 환경은 NA 로 처리한다.

try {
    $partOfDomain = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
} catch {
    $partOfDomain = $false
}

if (-not $partOfDomain) {
    return New-CheckResult -Code "W-60" -Status "NA" -Detail "도메인에 가입되어 있지 않은 워크그룹 환경으로 해당 정책이 적용되지 않음"
}

$path = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
$require = Test-RegistryValue -Path $path -Name "RequireSignOrSeal"
$seal = Test-RegistryValue -Path $path -Name "SealSecureChannel"
$sign = Test-RegistryValue -Path $path -Name "SignSecureChannel"

$evidence = "RequireSignOrSeal=$require SealSecureChannel=$seal SignSecureChannel=$sign"

if ($require -eq 1 -and $seal -eq 1 -and $sign -eq 1) {
    return New-CheckResult -Code "W-60" -Status "GOOD" -Detail "보안 채널 암호화/서명 관련 3개 정책이 모두 사용으로 설정됨" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-60" -Status "VULN" -Detail "보안 채널 암호화/서명 관련 정책 중 일부가 사용 안 함으로 설정됨" -Evidence $evidence
}
