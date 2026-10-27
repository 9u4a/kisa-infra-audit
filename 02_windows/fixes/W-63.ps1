# W-63 (중) 도메인 컨트롤러-사용자의 시간 동기화 [fix: auto]
# 원복: 실행 단위 전체만 — 보안 정책(secedit)은 항목별로 되돌릴 수 없어 '-Rollback <실행 폴더>' 로 이번 실행 전체를 되돌려야 함
# checks/W-63.ps1 과 동일하게 도메인 컨트롤러가 아니면 NA.

$productType = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType
if ($productType -ne 2) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "이 시스템은 도메인 컨트롤러가 아님"; $Global:FixEvidence = ""
    return
}

Set-FixSecPolicyValue -Section "Kerberos Policy" -Values @{ MaxClockSkew = 5 }
