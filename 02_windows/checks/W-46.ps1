# W-46 (상) SAM 파일 접근 통제 설정
# 판단 기준(가이드 원문): 양호 = SAM 파일 권한이 Administrators, System 그룹에만 부여된 경우
#                        취약 = 그 외 그룹에 권한이 있는 경우
# 최신 Windows 는 기본적으로 TrustedInstaller 가 소유자이며 SYSTEM 만 접근 가능한 것이 정상 기본값.
# W-R15: 이름 패턴('Administrators$|SYSTEM$') 대신 SID 로 비교한다(비영문 OS 에서 이름이 번역됨).
#   S-1-5-32-544 Administrators, S-1-5-18 SYSTEM, TrustedInstaller(NT SERVICE\TrustedInstaller 의 고정 서비스 SID)

$allowedSids = @(
    'S-1-5-32-544',
    'S-1-5-18',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
)

$path = Join-Path $env:SystemRoot "System32\config\SAM"
if (-not (Test-Path $path)) {
    return New-CheckResult -Code "W-46" -Status "ERROR" -Detail "$path 파일을 찾을 수 없음"
}

try {
    $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
} catch {
    return New-CheckResult -Code "W-46" -Status "ERROR" -Detail "SAM 파일 ACL 조회 실패: $($_.Exception.Message)"
}

$extra = @($rules | Where-Object { $_.AccessControlType -eq "Allow" -and $allowedSids -notcontains $_.IdentityReference.Value })
$evidence = ($rules | ForEach-Object { "$(ConvertFrom-Sid $_.IdentityReference.Value) ($($_.IdentityReference.Value))=$($_.FileSystemRights)($($_.AccessControlType))" }) -join "`n"

if ($extra.Count -eq 0) {
    return New-CheckResult -Code "W-46" -Status "GOOD" -Detail "SAM 파일 접근 권한이 Administrators/SYSTEM/TrustedInstaller 로만 제한되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-46" -Status "VULN" -Detail ("SAM 파일에 예상 외 권한이 부여됨: " + (($extra | ForEach-Object { ConvertFrom-Sid $_.IdentityReference.Value }) -join ", ")) -Evidence $evidence
}
