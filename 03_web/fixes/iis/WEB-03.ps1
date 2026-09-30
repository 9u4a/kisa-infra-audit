# WEB-03 (상) 비밀번호 파일 권한 관리 [IIS] — 조치 [fix: auto]
# checks/iis/WEB-03.ps1 과 동일한 SAM 파일에서 일반 사용자 ACE 만 제거한다.

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}

$samPath = Join-Path $env:SystemRoot "system32\config\SAM"
if (-not (Test-Path $samPath)) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "SAM 파일을 찾을 수 없음: $samPath"; $Global:FixEvidence = ""
    return
}

Remove-FixAclIdentity -Path $samPath -IdentityPatterns @('Everyone', 'BUILTIN\\Users', 'Authenticated Users')
