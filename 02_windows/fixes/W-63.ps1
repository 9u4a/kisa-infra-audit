# W-63 (중) 도메인 컨트롤러-사용자의 시간 동기화 [fix: auto]
# checks/W-63.ps1 과 동일하게 도메인 컨트롤러가 아니면 NA.

$productType = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType
if ($productType -ne 2) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "이 시스템은 도메인 컨트롤러가 아님"; $Global:FixEvidence = ""
    return
}

Set-FixSecPolicyValue -Section "Kerberos Policy" -Values @{ MaxClockSkew = 5 }
