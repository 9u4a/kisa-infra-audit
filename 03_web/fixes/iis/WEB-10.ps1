# WEB-10 (상) 불필요한 프록시 설정 제한 [IIS] — 조치 [fix: auto]

if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "IIS 가 설치되어 있지 않음"; $Global:FixEvidence = ""
    return
}

try {
    $section = Get-WebConfiguration -Filter "system.webServer/proxy" -PSPath "MACHINE/WEBROOT/APPHOST" -ErrorAction Stop
} catch {
    $section = $null
}

if (-not $section -or $section.enabled -ne $true) {
    $Global:FixStatus = "NA"; $Global:FixDetail = "ARR 프록시 기능이 이미 비활성화(또는 미설치)됨"; $Global:FixEvidence = ""
    return
}

Set-FixWebConfigProperty -Filter "system.webServer/proxy" -Name "enabled" -Value $false -PSPath "MACHINE/WEBROOT/APPHOST"
