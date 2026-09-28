# W-33 (하) HTTP/FTP/SMTP 배너 차단
# 판단 기준(가이드 원문): 양호 = HTTP/FTP/SMTP 접속 시 배너 정보가 보이지 않는 경우
# 자동화 범위: HTTP(W3SVC)는 실제 응답 헤더(Server)를 조회해 판정. FTP/SMTP는 서비스 구동
#             여부만 확인 가능하고 배너 문구 자체 확인은 어려워 구동 중이면 MANUAL.

$web = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
$ftp = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
$smtp = Get-Service -Name "SMTPSVC" -ErrorAction SilentlyContinue

$anyRunning = $false
$evidence = @()
$violations = @()
$manualNeeded = @()

if ($web -and $web.Status -eq "Running") {
    $anyRunning = $true
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $serverHeader = $resp.Headers["Server"]
    } catch {
        $serverHeader = $null
        if ($_.Exception.Response) { $serverHeader = $_.Exception.Response.Headers["Server"] }
    }
    $evidence += "HTTP Server 헤더: $serverHeader"
    if ($serverHeader) { $violations += "HTTP(Server 헤더 노출: $serverHeader)" }
}

if ($ftp -and $ftp.Status -eq "Running") {
    $anyRunning = $true
    $evidence += "FTP 서비스 구동 중 (배너 문구는 원격 접속 없이 확인 불가)"
    $manualNeeded += "FTP"
}

if ($smtp -and $smtp.Status -eq "Running") {
    $anyRunning = $true
    $evidence += "SMTP 서비스 구동 중 (배너 문구는 원격 접속 없이 확인 불가)"
    $manualNeeded += "SMTP"
}

if (-not $anyRunning) {
    return New-CheckResult -Code "W-33" -Status "GOOD" -Detail "HTTP/FTP/SMTP 서비스를 사용하지 않음"
}

if ($violations.Count -gt 0) {
    return New-CheckResult -Code "W-33" -Status "VULN" -Detail ("배너/버전 정보가 노출됨: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($manualNeeded.Count -gt 0) {
    return New-CheckResult -Code "W-33" -Status "MANUAL" -Detail ("HTTP 배너는 노출되지 않으나 " + ($manualNeeded -join ", ") + " 배너 문구는 원격 접속으로 직접 확인 필요") -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-33" -Status "GOOD" -Detail "HTTP 접속 시 Server 헤더가 노출되지 않음" -Evidence ($evidence -join "`n")
}
