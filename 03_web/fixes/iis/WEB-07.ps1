# WEB-07 (중) 웹 서비스 경로 내 불필요한 파일 제거 [IIS] — 조치 [fix: auto]
# checks/iis/WEB-07.ps1 과 동일한 대상 경로를 제거한다(내용 전체를 백업 후 삭제 -
# Backup-FixPathAndRemove 로 원복 가능).

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}

$sysDrive = $env:SystemDrive
$candidates = @(
    (Join-Path $sysDrive "inetpub\iissamples"),
    (Join-Path $sysDrive "inetpub\AdminScripts"),
    (Join-Path $sysDrive "inetpub\wwwroot\iishelp"),
    (Join-Path $sysDrive "Program Files\Common Files\System\msadc")
)

$removed = @()
foreach ($p in $candidates) {
    if (Test-Path $p) {
        Backup-FixPathAndRemove -Path $p
        $removed += $p
    }
}

if ($removed.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "기본 샘플/관리 스크립트 경로 제거: $($removed -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "제거 대상 경로가 없음(이미 정상)"
}
$Global:FixEvidence = ""
