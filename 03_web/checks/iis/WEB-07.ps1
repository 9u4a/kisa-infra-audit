# WEB-07 (중) 웹 서비스 경로 내 불필요한 파일 제거 [IIS]
# 판단 기준(가이드 원문): 양호 = 기본 생성되는 불필요 파일/디렉터리가 없는 경우
#                        취약 = 존재하는 경우
# 자동화 범위: IIS 설치 시 기본 제공되던 대표 샘플/관리 스크립트 경로의 존재 여부를 확인한다.

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-07" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

$sysDrive = $env:SystemDrive
$candidates = @(
    (Join-Path $sysDrive "inetpub\iissamples"),
    (Join-Path $sysDrive "inetpub\AdminScripts"),
    (Join-Path $sysDrive "inetpub\wwwroot\iishelp"),
    (Join-Path $sysDrive "Program Files\Common Files\System\msadc")
)

$found = @()
foreach ($p in $candidates) { if (Test-Path $p) { $found += $p } }
$evid = ($candidates | ForEach-Object { "$_ : $(if (Test-Path $_) { '존재' } else { '없음' })" }) -join "`n"

if ($found.Count -gt 0) {
    return New-CheckResult -Code "WEB-07" -Status "VULN" -Detail "기본 샘플/관리 스크립트 경로가 남아있음: $($found -join ', ')" -Evidence $evid
}
return New-CheckResult -Code "WEB-07" -Status "GOOD" -Detail "기본 샘플/관리 스크립트 경로가 존재하지 않음" -Evidence $evid
