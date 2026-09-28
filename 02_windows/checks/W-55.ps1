# W-55 (중) 사용자가 프린터 드라이버를 설치할 수 없게 함
# 판단 기준(가이드 원문): 양호 = 정책이 "사용"(AddPrinterDrivers=1) / 취약 = "사용 안 함"(0/미설정)

$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Providers\LanMan Print Services\Servers"
$val = Test-RegistryValue -Path $path -Name "AddPrinterDrivers"

if ($val -eq 1) {
    return New-CheckResult -Code "W-55" -Status "GOOD" -Detail "일반 사용자의 프린터 드라이버 설치가 제한되어 있음" -Evidence "AddPrinterDrivers=$val"
} else {
    return New-CheckResult -Code "W-55" -Status "VULN" -Detail "일반 사용자의 프린터 드라이버 설치가 제한되어 있지 않음" -Evidence "AddPrinterDrivers=$val"
}
