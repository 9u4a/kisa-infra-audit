# W-35 (중) 불필요한 ODBC/OLE-DB 데이터 소스와 드라이브 제거
# 판단 기준(가이드 원문): 양호 = 시스템 DSN 이 실제 사용 중인 경우 / 취약 = 사용하지 않는 경우
# "실제 사용 여부"는 응용프로그램 운영 현황을 알아야 하므로 자동 판정이 불가능하다.
# 자동화 범위: 등록된 시스템 DSN 목록을 근거로 제시, 최종 판단은 MANUAL.

$path = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"
try {
    $dsns = Get-ItemProperty -Path $path -ErrorAction Stop
    $names = $dsns.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { "$($_.Name) -> $($_.Value)" }
} catch {
    $names = @()
}

if ($names.Count -eq 0) {
    return New-CheckResult -Code "W-35" -Status "NA" -Detail "등록된 시스템 DSN(ODBC 데이터 소스)이 없음"
}

return New-CheckResult -Code "W-35" -Status "MANUAL" `
    -Detail "등록된 시스템 DSN의 실제 사용 여부는 응용프로그램 운영 현황 확인이 필요해 자동 판정할 수 없음. 아래 목록을 근거로 불필요한 항목 제거 검토 필요" `
    -Evidence ($names -join "`n")
