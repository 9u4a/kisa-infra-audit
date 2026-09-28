# D-13 (중) 불필요한 ODBC/OLE-DB 데이터 소스와 드라이브를 제거하여 사용 [MSSQL/Windows OS]
# 판단 기준(가이드 원문): "불필요한지"는 어떤 애플리케이션이 무엇을 쓰는지 알아야 판단 가능
# - 완전 자동 판정 불가. 등록된 시스템 DSN 목록을 증적으로 제공한다.

$path = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"
if (-not (Test-Path $path)) {
    return New-CheckResult -Code "D-13" -Status "GOOD" -Detail "등록된 시스템 ODBC 데이터 소스가 없음"
}
$dsns = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
$evidence = ($dsns.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object { "$($_.Name) = $($_.Value)" }) -join "`n"
if (-not $evidence) {
    return New-CheckResult -Code "D-13" -Status "GOOD" -Detail "등록된 시스템 ODBC 데이터 소스가 없음"
}
return New-CheckResult -Code "D-13" -Status "MANUAL" -Detail "등록된 시스템 ODBC 데이터 소스 목록 - 실제 사용 여부를 수동 검토하여 불필요한 항목 제거 필요" -Evidence $evidence
