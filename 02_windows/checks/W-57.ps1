# W-57 (하) 로그온 시 경고 메시지 설정
# 판단 기준(가이드 원문): 양호 = 로그온 경고 메시지 제목 및 내용이 설정된 경우
#                        취약 = 설정되어 있지 않은 경우

$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$caption = Test-RegistryValue -Path $path -Name "LegalNoticeCaption"
$text = Test-RegistryValue -Path $path -Name "LegalNoticeText"

$evidence = "LegalNoticeCaption='$caption' LegalNoticeText 길이=$($text.Length)"

if ($caption -and $text) {
    return New-CheckResult -Code "W-57" -Status "GOOD" -Detail "로그온 경고 메시지 제목과 내용이 모두 설정되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-57" -Status "VULN" -Detail "로그온 경고 메시지 제목 또는 내용이 설정되어 있지 않음" -Evidence $evidence
}
