# W-34 (중) Telnet 서비스 비활성화 [fix: auto]
# checks/W-34.ps1: 취약 = Telnet 구동 중이며 NTLM 인증이 아님. tlntadmn 으로 인증 방식을
# NTLM 으로 제한한다. tlntadmn 설정은 레지스트리 헬퍼로 백업/원복할 수 없어(레거시 텔넷 서버
# 자체 설정 저장소) Restore-FixItem 표준 원복 대상에 포함되지 않는다 - Windows Server 2016+
# 에는 이 서비스 자체가 없어 실질적 영향은 제한적이다.

$svc = Get-Service -Name "TlntSvr" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    $Global:FixStatus = "NA"; $Global:FixDetail = "Telnet 서비스를 사용하지 않음"; $Global:FixEvidence = ""
    return
}

$tlntadmn = Get-Command "tlntadmn.exe" -ErrorAction SilentlyContinue
if (-not $tlntadmn) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "tlntadmn 명령을 찾을 수 없음"; $Global:FixEvidence = ""
    return
}

try {
    $out = & tlntadmn.exe config sec /NTLM:yes 2>&1 | Out-String
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "Telnet 인증 방식을 NTLM 전용으로 설정함"
    $Global:FixEvidence = $out
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "tlntadmn 설정 실패: $($_.Exception.Message)"
    $Global:FixEvidence = ""
}
