# W-35 케이스. 가이드: 양호 = 시스템 DSN 을 현재 사용 / 취약 = 사용하지 않음. "사용 여부"는 응용프로그램 운영 현황이 필요해
# DSN 이 있으면 MANUAL(manual-by-design), 없으면 NA.
@{
    States = [ordered]@{
        'no-dsn'     = @{
            Reg   = @(@{ P = 'HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources'; N = 'KisaCaseDSN'; V = $null })
            Check = { $k = 'HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources'; $n = if (Test-Path $k) { @((Get-Item $k).GetValueNames() | Where-Object { $_ }).Count } else { 0 }; if ($n -eq 0) { $true } else { "DSN $n 개" } }
        }
        'system-dsn' = @{ Reg = @(@{ P = 'HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources'; N = 'KisaCaseDSN'; V = 'SQL Server'; T = 'String' }) }
    }
}
