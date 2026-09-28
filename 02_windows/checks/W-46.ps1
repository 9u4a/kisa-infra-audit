# W-46 (상) SAM 파일 접근 통제 설정
# 판단 기준(가이드 원문): 양호 = SAM 파일 권한이 Administrators, System 그룹에만 부여된 경우
#                        취약 = 그 외 그룹에 권한이 있는 경우
# 최신 Windows 는 기본적으로 TrustedInstaller 가 소유자이며 SYSTEM 만 접근 가능한 것이 정상 기본값.

$path = Join-Path $env:SystemRoot "System32\config\SAM"
if (-not (Test-Path $path)) {
    return New-CheckResult -Code "W-46" -Status "ERROR" -Detail "$path 파일을 찾을 수 없음"
}

try {
    $acl = Get-Acl -Path $path -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-46" -Status "ERROR" -Detail "SAM 파일 ACL 조회 실패: $($_.Exception.Message)"
}

$allowedPattern = 'Administrators$|SYSTEM$|TrustedInstaller$'
$extra = $acl.Access | Where-Object { $_.AccessControlType -eq "Allow" -and $_.IdentityReference -notmatch $allowedPattern }
$evidence = ($acl.Access | ForEach-Object { "$($_.IdentityReference)=$($_.FileSystemRights)($($_.AccessControlType))" }) -join "`n"

if ($extra.Count -eq 0) {
    return New-CheckResult -Code "W-46" -Status "GOOD" -Detail "SAM 파일 접근 권한이 Administrators/SYSTEM/TrustedInstaller 로만 제한되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-46" -Status "VULN" -Detail ("SAM 파일에 예상 외 권한이 부여됨: " + (($extra | ForEach-Object { $_.IdentityReference }) -join ", ")) -Evidence $evidence
}
