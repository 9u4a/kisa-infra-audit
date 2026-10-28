# W-34 (중) Telnet 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = Telnet 미구동 또는 인증 방법이 NTLM / 취약 = 구동 중이며 NTLM 아님
# 참고: Windows 2016 이상은 Telnet 서버 자체가 제공되지 않음.
# W-R15: tlntadmn 출력은 OS 언어로 번역된다(한글판은 "Password" 대신 "암호" 등). 예전에는 영문 "Password" 가
# 없으면 GOOD 이었다. 값 자체인 "NTLM" 이 있는 줄을 찾아 그 줄의 값이 NTLM 하나뿐일 때만 GOOD, 다른 방식이
# 함께 있으면 VULN, 그 줄을 찾지 못하면(형식 해석 불가) MANUAL. W-R16: 시간 제한.

try { $svc = Get-ServiceChecked -Name "TlntSvr" }
catch { return New-CheckResult -Code "W-34" -Status "ERROR" -Detail "Telnet(TlntSvr) 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-34" -Status "GOOD" -Detail "Telnet 서비스가 설치되어 있지 않거나 중지 상태임"
}

$tlntadmn = Get-Command "tlntadmn.exe" -ErrorAction SilentlyContinue
if (-not $tlntadmn) {
    return New-CheckResult -Code "W-34" -Status "MANUAL" -Detail "Telnet 서비스가 구동 중이나 tlntadmn 명령을 찾을 수 없어 인증 방식을 자동 확인할 수 없음"
}

try {
    $r = Invoke-NativeCommand -FilePath $tlntadmn.Source -ArgumentList @('config') -TimeoutSec 30
} catch {
    return New-CheckResult -Code "W-34" -Status "ERROR" -Detail "tlntadmn config 실행 실패: $($_.Exception.Message)"
}
if ($r.TimedOut -or $r.ExitCode -ne 0) {
    return New-CheckResult -Code "W-34" -Status "ERROR" -Detail "tlntadmn config 실행 실패($(if ($r.TimedOut) { '시간 초과' } else { "exit=$($r.ExitCode)" }))" -Evidence (($r.Output -join "`n") + $r.ErrorText)
}
$out = ($r.Output -join "`n").Trim()

$authLine = @($r.Output | Where-Object { $_ -match 'NTLM' }) | Select-Object -First 1
if (-not $authLine) {
    return New-CheckResult -Code "W-34" -Status "MANUAL" -Detail "tlntadmn 출력에서 인증 방식 줄을 찾지 못함 — 인증 방식을 수동 확인 필요" -Evidence $out
}
$value = if ($authLine -match '[:=]\s*(.+)$') { $Matches[1].Trim() } else { $authLine.Trim() }
$methods = @($value -split '[,;/\s]+' | Where-Object { $_ })

if ($methods.Count -eq 1 -and $methods[0] -ieq 'NTLM') {
    return New-CheckResult -Code "W-34" -Status "GOOD" -Detail "Telnet 서비스가 구동 중이나 인증 방식이 NTLM 으로 제한되어 있음" -Evidence $out
} else {
    return New-CheckResult -Code "W-34" -Status "VULN" -Detail "Telnet 서비스가 구동 중이며 NTLM 외 인증 방식이 허용되어 있음($value)" -Evidence $out
}
