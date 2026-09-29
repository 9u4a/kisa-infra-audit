# WEB-03 (상) 비밀번호 파일 권한 관리 [IIS]
# 판단 기준(가이드 원문): 양호 = 비밀번호 파일 권한이 600 이하 / 취약 = 600 초과
# 자동화 범위: IIS/Windows는 SAM 파일(%systemroot%\system32\config\SAM)에 계정 비밀번호
# 해시를 저장한다. Unix 권한 600(소유자만 읽기/쓰기)에 대응하는 Windows 기준은 "일반 사용자
# 계정(Everyone/Users/Authenticated Users)에게 허용된 ACE가 없어야 함"으로 판단한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-03" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

$samPath = Join-Path $env:SystemRoot "system32\config\SAM"
if (-not (Test-Path $samPath)) {
    return New-CheckResult -Code "WEB-03" -Status "ERROR" -Detail "SAM 파일을 찾을 수 없음: $samPath"
}

try {
    $acl = Get-Acl -Path $samPath -ErrorAction Stop
} catch {
    return New-CheckResult -Code "WEB-03" -Status "ERROR" -Detail "SAM 파일 ACL 조회 실패(권한 부족 가능): $($_.Exception.Message)"
}

$riskyIdentities = 'Everyone', 'BUILTIN\\Users', '\\Users$', 'Authenticated Users'
$pattern = ($riskyIdentities -join '|')
$badAce = $acl.Access | Where-Object {
    $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -match $pattern
}

$evid = ($acl.Access | ForEach-Object { "$($_.IdentityReference): $($_.FileSystemRights) ($($_.AccessControlType))" }) -join "`n"

if ($badAce) {
    return New-CheckResult -Code "WEB-03" -Status "VULN" -Detail "SAM 파일에 일반 사용자(Everyone/Users/Authenticated Users) 접근 권한이 허용되어 있음" -Evidence $evid
}
return New-CheckResult -Code "WEB-03" -Status "GOOD" -Detail "SAM 파일에 일반 사용자 접근 권한이 없음" -Evidence $evid
