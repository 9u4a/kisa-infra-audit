# D-13 (중) 불필요한 ODBC/OLE-DB 데이터 소스와 드라이브를 제거하여 사용 [MSSQL/Windows OS] — 조치 [fix: param]
# 값: dsns=제거할 시스템 DSN 이름(쉼표 구분) - 진단 증적의 시스템 ODBC 데이터 소스(64/32비트) 중 쓰지 않는 것
# 변경: 지정 DSN 의 ODBC Data Sources 등록 값과 ODBC.INI\<이름> 키를 제거(64·32비트 중 있는 쪽) - 값·키를 백업(reg export)해 원복 시 되살림
# 영향: 지정 DSN 으로 접속하던 애플리케이션·보고서 도구의 DB 연결이 즉시 실패
# 가이드 조치 방법: 불필요한 ODBC 데이터 소스 제거. 사용 여부는 사람이 판단한다(진단 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 이름에 \ 와 제어문자 없음·64/32비트 시스템 DSN 목록에 있음·중복 없음. 원격 모드(-SqlHost 가
# 다른 서버)에서는 이 PC 의 레지스트리가 대상이 아니라 바꾸지 않는다.

$vals = @(Get-FixParam -Key "dsns")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 D-13.dsns 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
if (Test-MssqlRemoteTarget) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "원격 모드 - ODBC 데이터 소스는 DB 서버의 로컬 레지스트리라 이 PC 에서 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$roots = @("HKLM:\SOFTWARE\ODBC\ODBC.INI", "HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI")
$errs = @(); $seen = @{}; $plan = @()
foreach ($d in $vals) {
    if ($seen.ContainsKey($d.ToLowerInvariant())) { $errs += "${d}: 값에 두 번 나옴"; continue }
    $seen[$d.ToLowerInvariant()] = $true
    if ($d -match '[\\\x00-\x1f]') { $errs += "${d}: DSN 이름에 쓸 수 없는 문자"; continue }
    $hit = @()
    foreach ($r in $roots) {
        $src = Join-Path $r "ODBC Data Sources"
        if (-not (Test-Path -LiteralPath $src)) { continue }
        try { $names = @((Get-Item -LiteralPath $src -ErrorAction Stop).GetValueNames()) }
        catch { $errs += "${d}: $src 읽기 실패($($_.Exception.Message))"; continue }
        if ($names -contains $d) { $hit += $r }
    }
    if ($hit.Count -eq 0) { $errs += "${d}: 시스템 DSN 목록(64/32비트)에 없음"; continue }
    foreach ($r in $hit) { $plan += [PSCustomObject]@{ Root = $r; Name = $d } }
}
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}
$done = @(); $failed = @()
foreach ($p in $plan) {
    $src = Join-Path $p.Root "ODBC Data Sources"
    try {
        [void](Remove-FixRegistryKeyWithBackup -Path (Join-Path $p.Root $p.Name))
        Remove-FixRegistryValue -Path $src -Name $p.Name
        if (@((Get-Item -LiteralPath $src).GetValueNames()) -contains $p.Name) { throw "등록 값이 남음" }
        $done += "$($p.Name)($($p.Root))"
    } catch {
        if ($_.Exception.Message.StartsWith("[백업 실패]")) { throw }
        $failed += "$($p.Name)($($p.Root)): $($_.Exception.Message)"
    }
}
$Global:FixEvidence = ($done -join "`n")
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "DSN 제거 실패: $($failed -join ' / ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 시스템 DSN 을 제거함(백업 후): $($done -join ', ')"
}
