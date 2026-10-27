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
$unverified = @()

if ($web -and $web.Status -eq "Running") {
    $anyRunning = $true
    # 운영 IIS 에 실제 요청이 1~2회 발생한다(앱 풀 기동·접속 로그 기록). 유휴 앱 풀은 첫 요청이
    # cold start 로 늦을 수 있어 1회 재시도한다. 끝내 응답이 없으면 "헤더 없음 = 양호"로 단정하지
    # 않고 ERROR 로 남긴다(예전에는 시간 초과도 GOOD 이 됐다 - CI 러너에서 실제로 재현됨).
    $serverHeader = $null; $gotResponse = $false; $lastErr = ""
    foreach ($timeoutSec in 5, 15) {
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec $timeoutSec -ErrorAction Stop
            $serverHeader = $resp.Headers["Server"]; $gotResponse = $true; break
        } catch {
            $r = $_.Exception.Response
            if ($r) {
                # 4xx/5xx 도 응답이다. PS 5.1 은 HttpWebResponse, PS 7 은 HttpResponseMessage 라 헤더 접근법이 다르다.
                $gotResponse = $true
                if ($r -is [System.Net.HttpWebResponse]) { $serverHeader = $r.Headers["Server"] }
                else { try { $serverHeader = @($r.Headers.Server | ForEach-Object { $_.ToString() }) -join " " } catch { $serverHeader = $null } }
                break
            }
            $lastErr = $_.Exception.Message
        }
    }
    $serverHeader = "$(@($serverHeader) -join ' ')".Trim()
    if (-not $gotResponse) {
        $unverified += "HTTP(localhost 응답 없음: $lastErr)"
        $evidence += "HTTP Server 헤더: 확인 불가(응답 없음)"
    } else {
        $evidence += "HTTP Server 헤더: $serverHeader"
        if ($serverHeader) { $violations += "HTTP(Server 헤더 노출: $serverHeader)" }
    }
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
} elseif ($unverified.Count -gt 0) {
    return New-CheckResult -Code "W-33" -Status "ERROR" -Detail ("배너 노출 여부를 확인하지 못함: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($manualNeeded.Count -gt 0) {
    return New-CheckResult -Code "W-33" -Status "MANUAL" -Detail ("HTTP 배너는 노출되지 않으나 " + ($manualNeeded -join ", ") + " 배너 문구는 원격 접속으로 직접 확인 필요") -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-33" -Status "GOOD" -Detail "HTTP 접속 시 Server 헤더가 노출되지 않음" -Evidence ($evidence -join "`n")
}
