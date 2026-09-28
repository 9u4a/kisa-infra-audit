# W-59 (중) LAN Manager 인증 수준
# 판단 기준(가이드 원문): 양호 = "NTLMv2 응답만 보냄"(수준 3) 이상 / 취약 = LM/NTLM 허용(수준 3 미만)
# LmCompatibilityLevel: 0~2=LM/NTLM 허용(취약) 3=NTLMv2만 보냄(양호) 4~5=NTLMv2만+서버측 거부(양호)
# 참고: 이 키가 없으면 Windows Vista/Server 2008 이후 기본값은 3(양호)이다.

$val = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel"
$level = if ($null -eq $val) { 3 } else { [int]$val }

if ($level -ge 3) {
    return New-CheckResult -Code "W-59" -Status "GOOD" -Detail "LAN Manager 인증 수준이 ${level}(NTLMv2 응답만 보냄 이상)로 설정됨" -Evidence "LmCompatibilityLevel=$val (적용값 $level)"
} else {
    return New-CheckResult -Code "W-59" -Status "VULN" -Detail "LAN Manager 인증 수준이 ${level}로 LM/NTLM 인증이 허용됨" -Evidence "LmCompatibilityLevel=$val (적용값 $level)"
}
