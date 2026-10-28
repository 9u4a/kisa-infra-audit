# D-13 (중) 불필요한 ODBC/OLE-DB 데이터 소스와 드라이브를 제거하여 사용 [MSSQL/Windows OS]
# 판단 기준(가이드 원문): "불필요한지"는 어떤 애플리케이션이 무엇을 쓰는지 알아야 판단 가능
# - 완전 자동 판정 불가. 등록된 시스템 DSN 목록을 증적으로 제공한다.
# 진단 검수 D-R1: -SqlHost 가 다른 서버면 이 PC 의 레지스트리를 보게 되므로 MANUAL.
# 진단 검수 D-R11: 32비트 시스템 DSN(WOW6432Node)도 함께 본다 - 예전에는 64비트 키만 봐서 32비트 DSN 만 있으면 GOOD.

if (Test-MssqlRemoteTarget) {
    return New-CheckResult -Code "D-13" -Status "MANUAL" -Detail "원격 모드 - DB 서버 호스트에서 실행 필요: ODBC 데이터 소스는 DB 서버의 로컬 레지스트리라 이 PC(-SqlHost $env:DB_HOST)에서 확인할 수 없음"
}

$paths = @(
    @{ Label = "64bit"; Path = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources" },
    @{ Label = "32bit"; Path = "HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI\ODBC Data Sources" }
)
$lines = @()
foreach ($p in $paths) {
    if (-not (Test-Path $p.Path)) { continue }
    try {
        $dsns = Get-ItemProperty -Path $p.Path -ErrorAction Stop
    } catch {
        return New-CheckResult -Code "D-13" -Status "ERROR" -Detail "ODBC 데이터 소스 레지스트리를 읽지 못함($($p.Label)): $($_.Exception.Message)"
    }
    $lines += @($dsns.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object { "[$($p.Label)] $($_.Name) = $($_.Value)" })
}
if ($lines.Count -eq 0) {
    return New-CheckResult -Code "D-13" -Status "GOOD" -Detail "등록된 시스템 ODBC 데이터 소스가 없음(64/32비트)"
}
return New-CheckResult -Code "D-13" -Status "MANUAL" -Detail "등록된 시스템 ODBC 데이터 소스 목록 - 실제 사용 여부를 수동 검토하여 불필요한 항목 제거 필요" -Evidence ($lines -join "`n")
