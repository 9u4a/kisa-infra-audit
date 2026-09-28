# W-34 (중) Telnet 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = Telnet 미구동 또는 인증 방법이 NTLM / 취약 = 구동 중이며 NTLM 아님
# 참고: Windows 2016 이상은 Telnet 서버 자체가 제공되지 않음.

$svc = Get-Service -Name "TlntSvr" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-34" -Status "GOOD" -Detail "Telnet 서비스가 설치되어 있지 않거나 중지 상태임"
}

$tlntadmn = Get-Command "tlntadmn.exe" -ErrorAction SilentlyContinue
if (-not $tlntadmn) {
    return New-CheckResult -Code "W-34" -Status "MANUAL" -Detail "Telnet 서비스가 구동 중이나 tlntadmn 명령을 찾을 수 없어 인증 방식을 자동 확인할 수 없음"
}

try {
    $out = & tlntadmn.exe config 2>&1 | Out-String
} catch {
    return New-CheckResult -Code "W-34" -Status "MANUAL" -Detail "tlntadmn config 실행 실패: $($_.Exception.Message)"
}

if ($out -match "NTLM" -and $out -notmatch "Password") {
    return New-CheckResult -Code "W-34" -Status "GOOD" -Detail "Telnet 서비스가 구동 중이나 인증 방식이 NTLM 으로 제한되어 있음" -Evidence $out
} else {
    return New-CheckResult -Code "W-34" -Status "VULN" -Detail "Telnet 서비스가 구동 중이며 NTLM 외 인증 방식(Password)이 허용되어 있음" -Evidence $out
}
