# W-33 (하) HTTP/FTP/SMTP 배너 차단
# 판단 기준(가이드 원문): 양호 = HTTP/FTP/SMTP 접속 시 배너 정보가 보이지 않는 경우
# 자동화 범위: HTTP(W3SVC)는 실제 응답 헤더(Server)를 조회해 판정. FTP/SMTP는 서비스 구동
#             여부만 확인 가능하고 배너 문구 자체 확인은 어려워 구동 중이면 MANUAL.

# 서비스 조회 실패(비관리자 배치 실행 등)를 "미사용 = GOOD" 으로 읽지 않는다(CI 실측: 비관리자 실행에서 VULN→GOOD)
try {
    $web = Get-ServiceChecked -Name "W3SVC"
    $ftp = Get-ServiceChecked -Name "FTPSVC"
    $smtp = Get-ServiceChecked -Name "SMTPSVC"
} catch {
    return New-CheckResult -Code "W-33" -Status "ERROR" -Detail "웹/FTP/SMTP 서비스 상태를 조회하지 못함: $($_.Exception.Message)"
}

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
    # W-R15: 리디렉션을 따라가지 않고(AllowAutoRedirect=false) 시스템 프록시도 쓰지 않는다(Proxy=$null) - 예전
    # Invoke-WebRequest 는 localhost 의 302 응답을 따라 외부 호스트로 요청을 보낼 수 있었다. 3xx 응답의 Server
    # 헤더만으로 판정한다.
    $serverHeader = $null; $gotResponse = $false; $lastErr = ""
    foreach ($timeoutSec in 5, 15) {
        $resp = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create("http://localhost/")
            $req.AllowAutoRedirect = $false
            $req.Proxy = $null
            $req.Method = "GET"
            $req.Timeout = $timeoutSec * 1000
            $req.ReadWriteTimeout = $timeoutSec * 1000
            $resp = $req.GetResponse()
            $serverHeader = $resp.Headers["Server"]; $gotResponse = $true; break
        } catch [System.Net.WebException] {
            # 4xx/5xx 도 응답이다(WebException.Response 에 헤더가 있음)
            $r = $_.Exception.Response
            if ($r) { $gotResponse = $true; $serverHeader = $r.Headers["Server"]; $r.Close(); break }
            $lastErr = $_.Exception.Message
        } catch {
            $lastErr = $_.Exception.Message
        } finally {
            if ($resp) { $resp.Close() }
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
