# W-46 (상) SAM 파일 접근 통제 설정 [fix: auto]
# checks/W-46.ps1: 양호 = Administrators/SYSTEM/TrustedInstaller 외 권한이 없는 경우.
# 실제로 부여되어 있는 "그 외" 계정만 골라 제거한다(허용 목록은 고정값이라 U-28류 문제 아님).

$path = Join-Path $env:SystemRoot "System32\config\SAM"
if (-not (Test-Path $path)) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "$path 파일을 찾을 수 없음"; $Global:FixEvidence = ""
    return
}

try {
    $acl = Get-Acl -Path $path -ErrorAction Stop
} catch {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "SAM 파일 ACL 조회 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""
    return
}

$allowedPattern = 'Administrators$|SYSTEM$|TrustedInstaller$'
$extraIdentities = @($acl.Access | Where-Object { $_.AccessControlType -eq "Allow" -and $_.IdentityReference -notmatch $allowedPattern } |
    ForEach-Object { [regex]::Escape($_.IdentityReference.Value) })

if ($extraIdentities.Count -eq 0) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "이미 Administrators/SYSTEM/TrustedInstaller 로만 제한되어 있음"; $Global:FixEvidence = ""
    return
}

Remove-FixAclIdentity -Path $path -IdentityPatterns $extraIdentities
