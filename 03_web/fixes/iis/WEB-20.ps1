# WEB-20 (상) SSL/TLS 활성화 [IIS] — 조치 [fix: param]
# 값: thumbprint=사용할 서버 인증서 지문(로컬 컴퓨터 개인 저장소 Cert:\LocalMachine\My 에 개인 키와 함께 설치된 것)
# 변경: https 바인딩이 없는 사이트에 https 바인딩(*:443, 사이트 http 바인딩의 호스트 헤더) 추가 + 인증서 연결 - 원복 시 바인딩과 이 조치가
#       만든 인증서 연결(0.0.0.0!443)을 지움
# 영향: 즉시 443 포트로 HTTPS 를 받음 — 같은 포트를 쓰는 다른 프로그램·사이트와 충돌하면 그 사이트가 시작되지 않을 수 있음
# 가이드 조치 방법: SSL/TLS 활성화. 신뢰할 수 있는 인증서를 스크립트가 발급할 수 없어 manual 이었다 - 1.7.0 값 지정 조치로 운영자가
# 설치해 둔 인증서 지문을 정책 값으로 받는다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 지문 형식(16진수 40자)·LocalMachine\My 에 있고 개인 키 있음·만료 아님, https 바인딩이
# 없는 사이트들의 호스트 헤더가 겹치지 않음(*:443 하나를 여러 사이트가 함께 쓸 수 없음), 0.0.0.0!443 에 다른 인증서가 이미 연결돼 있지 않음.

$vals = @(Get-FixParam -Key "thumbprint")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 WEB-20.thumbprint 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "IIS 가 설치되어 있지 않아 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @()
$tp = ("$($vals[0])" -replace '\s', '').ToUpperInvariant()
if ($vals.Count -ne 1) { $errs += "thumbprint 는 하나여야 함" }
if ($tp -notmatch '^[0-9A-F]{40}$') { $errs += "${tp}: 인증서 지문 형식(16진수 40자)이 아님" }
else {
    $c = Get-ChildItem -Path "Cert:\LocalMachine\My\$tp" -ErrorAction SilentlyContinue
    if (-not $c) { $errs += "${tp}: Cert:\LocalMachine\My 에 없는 인증서" }
    elseif (-not $c.HasPrivateKey) { $errs += "${tp}: 개인 키가 없는 인증서" }
    elseif ($c.NotAfter -lt (Get-Date)) { $errs += "${tp}: 만료된 인증서($($c.NotAfter))" }
}
$targets = @()
foreach ($site in @(Get-IisSiteNames)) {
    if (@(Get-WebBinding -Name $site -Protocol https -ErrorAction SilentlyContinue).Count -gt 0) { continue }
    $h = @(Get-WebBinding -Name $site -Protocol http -ErrorAction SilentlyContinue | ForEach-Object { ("$($_.bindingInformation)" -split ':', 3)[2] } | Select-Object -First 1)
    $targets += [PSCustomObject]@{ Site = $site; HostHeader = "$($h[0])" }
}
if ($targets.Count -eq 0) { $errs += "https 바인딩이 없는 사이트가 없음(조치 대상 없음)" }
$dupHeaders = @($targets | Group-Object HostHeader | Where-Object { $_.Count -gt 1 })
if ($dupHeaders.Count -gt 0) { $errs += "호스트 헤더가 같은(또는 없는) 사이트가 여럿 - *:443 을 함께 쓸 수 없어 수동 조치: $(($dupHeaders | ForEach-Object { $_.Group.Site -join '/' }) -join ', ')" }
$sslNow = Get-Item -LiteralPath "IIS:\SslBindings\0.0.0.0!443" -ErrorAction SilentlyContinue
if ($sslNow -and "$($sslNow.Thumbprint)" -ne $tp) { $errs += "0.0.0.0!443 에 다른 인증서($($sslNow.Thumbprint))가 이미 연결돼 있음 - 수동 조치" }
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

$done = @(); $failed = @()
foreach ($t in $targets) {
    try { Add-FixIisHttpsBinding -Site $t.Site -Thumbprint $tp -Port 443 -HostHeader $t.HostHeader; $done += "$($t.Site)(*:443:$($t.HostHeader))" }
    catch {
        if ($_.Exception.Message.StartsWith("[백업 실패]")) { throw }
        $failed += "$($t.Site): $($_.Exception.Message)"
    }
}
$Global:FixEvidence = (@(Get-IisSiteNames) | ForEach-Object { "[$_] https 바인딩 수 = $(@(Get-WebBinding -Name $_ -Protocol https -ErrorAction SilentlyContinue).Count)" }) -join "`n"
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "https 바인딩 추가 실패: $($failed -join ' / ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "https 바인딩(인증서 $tp)을 추가함: $($done -join ', ')"
}
