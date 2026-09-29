# W-39 (상) 백신 프로그램 업데이트 [fix: auto]
# checks/W-39.ps1: Windows Defender 서명이 7일 이상 오래됐거나(자동 갱신 가능) 백신 자체가
# 없는 경우(설치는 자동화 불가) VULN. 전자만 안전하게 자동 조치할 수 있다.

try {
    Update-MpSignature -ErrorAction Stop
    Start-Sleep -Seconds 2
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.AntivirusSignatureAge -le 7) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "Windows Defender 서명 업데이트 실행함(AntivirusSignatureAge=$($mp.AntivirusSignatureAge)일)"
        $Global:FixEvidence = ""
    } else {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "서명 업데이트를 실행했으나 여전히 오래됨(AntivirusSignatureAge=$($mp.AntivirusSignatureAge)일) - 네트워크/오프라인 정의 배포 정책 확인 필요"
        $Global:FixEvidence = ""
    }
} catch {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Windows Defender 를 사용할 수 없거나 서명 업데이트 실패(타사 백신이거나 백신 미설치 - 설치 자체는 자동화 대상이 아님): $($_.Exception.Message)"
    $Global:FixEvidence = ""
}
