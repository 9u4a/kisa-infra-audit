# WEB-07 (중) 웹 서비스 경로 내 불필요한 파일 제거 [IIS] — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# checks/iis/WEB-07.ps1 과 동일한 대상 경로를 제거한다(내용 전체를 백업 후 삭제 -
# Backup-FixPathAndRemove 로 원복 가능).
# C-WEB07(1.4.0): Windows 구성요소(TrustedInstaller 소유, 예: Windows Server 의 MDAC msadc)는 관리자도 다 지울 수 없어
# 예전에는 일부만 지워진 채 APPLIED 로 보고됐다(CI 실측). 지우면 OS 구성요소 서비스(업데이트·복구)와도 충돌하므로 자동
# 삭제하지 않고 ERROR(수동 조치 안내)로 끝낸다 - 재검증이 VULN 이라 fix.ps1 이 이 항목에서 지운 다른 경로까지 원복한다.

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
$trustedInstaller = "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"

$removed = @()
$protected = @()
foreach ($p in $candidates) {
    if (-not (Test-Path $p)) { continue }
    $owner = try { (Get-Acl -LiteralPath $p -ErrorAction Stop).GetOwner([System.Security.Principal.SecurityIdentifier]).Value } catch { "" }
    if ($owner -eq $trustedInstaller) { $protected += $p; continue }
    Backup-FixPathAndRemove -Path $p
    $removed += $p
}

if ($protected.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "Windows 구성요소(TrustedInstaller 소유) 경로는 자동 삭제하지 않음 - 필요 여부 확인 후 수동 조치(Windows 기능 제거 등): $($protected -join ', ')$(if ($removed) { " / 함께 제거했던 경로(원복 대상): $($removed -join ', ')" })"
} elseif ($removed.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "기본 샘플/관리 스크립트 경로 제거: $($removed -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "제거 대상 경로가 없음(이미 정상)"
}
$Global:FixEvidence = ""
