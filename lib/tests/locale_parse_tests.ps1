# lib/tests/locale_parse_tests.ps1 — 로캘 의존 명령 출력 파싱 단위 테스트(1.5.0 C6, KNOWN_ISSUES L-02)
# 대상: lib/Common.psm1 의 ConvertFrom-AuditPolBackup(W-40) / Get-BcdEditEntryCount(PC-08) / ConvertFrom-TlntadmnConfig(W-34).
# 픽스처(lib/tests/fixtures/locale/, UTF-8):
#   - auditpol_backup_*.csv, bcdedit_enum_{ko-KR,en-US}.txt : 한글 Windows 11 에서 읽기 전용 명령으로 실제 수집
#     (ko-KR = chcp 949 콘솔, en-US = chcp 437 콘솔 - 콘솔 코드페이지에 따라 표시 언어가 바뀐다). 컴퓨터 이름은 HOST 로 바꿈.
#     en-US auditpol 은 머리글만 영문이고 하위 범주 이름은 한글이 cp437 로 깨진 "?" 그대로다(실제 출력 형태).
#   - bcdedit_enum_multiboot_ko-KR.txt : 위 한글 실측본에 부트 로더 항목 하나를 덧붙인 파생본.
#   - tlntadmn_config_*.txt : 합성. Telnet 서버는 Server 2016 / Windows 10 이후 제공되지 않아 실측 불가.
# Linux pwsh 7(CI static-analysis)에서도 돈다 - 외부 명령을 실행하지 않고 파싱 함수만 부른다.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Common.psm1') -Force
$fx = Join-Path $PSScriptRoot 'fixtures/locale'
$script:fail = 0
function Assert-Equal($name, $actual, $expected) {
    if ("$actual" -ceq "$expected") { Write-Host "  ok   $name" }
    else { Write-Host "  FAIL $name : expected '$expected', got '$actual'"; $script:fail++ }
}
function Read-Fixture($name) { return @(Get-Content -LiteralPath (Join-Path $fx $name) -Encoding UTF8) }

Write-Host "[auditpol /backup]"
# 실측값: 로그온(9215)=3, 민감한 권한 사용(9228)=0, 감사 정책 변경(922F)=1, 기타 계정 관리(923A)=0, 자격 증명 유효성 검사(923F)=0
foreach ($loc in 'ko-KR', 'en-US') {
    $m = ConvertFrom-AuditPolBackup -Lines (Read-Fixture "auditpol_backup_$loc.csv")
    Assert-Equal "$loc parsed" ($null -ne $m) $true
    Assert-Equal "$loc row count" $m.Count 60
    Assert-Equal "$loc Logon" $m['{0CCE9215-69AE-11D9-BED3-505054503030}'] 3
    Assert-Equal "$loc Sensitive Privilege Use" $m['{0CCE9228-69AE-11D9-BED3-505054503030}'] 0
    Assert-Equal "$loc Audit Policy Change" $m['{0CCE922F-69AE-11D9-BED3-505054503030}'] 1
    Assert-Equal "$loc lower-case lookup" $m['{0cce9215-69ae-11d9-bed3-505054503030}'] 3
}
Assert-Equal "header only -> null" ($null -eq (ConvertFrom-AuditPolBackup -Lines @((Read-Fixture 'auditpol_backup_ko-KR.csv')[0]))) $true
Assert-Equal "garbage -> null" ($null -eq (ConvertFrom-AuditPolBackup -Lines @('액세스가 거부되었습니다.', ''))) $true
Assert-Equal "empty -> null" ($null -eq (ConvertFrom-AuditPolBackup -Lines @())) $true

Write-Host "[bcdedit /enum]"
Assert-Equal "ko-KR single OS" (Get-BcdEditEntryCount -Text ((Read-Fixture 'bcdedit_enum_ko-KR.txt') -join "`n")) 2
Assert-Equal "en-US single OS" (Get-BcdEditEntryCount -Text ((Read-Fixture 'bcdedit_enum_en-US.txt') -join "`n")) 2
Assert-Equal "ko-KR multiboot" (Get-BcdEditEntryCount -Text ((Read-Fixture 'bcdedit_enum_multiboot_ko-KR.txt') -join "`n")) 3
Assert-Equal "CRLF text" (Get-BcdEditEntryCount -Text ((Read-Fixture 'bcdedit_enum_ko-KR.txt') -join "`r`n")) 2
Assert-Equal "access denied -> 0" (Get-BcdEditEntryCount -Text "부팅 구성 데이터 저장소를 열 수 없습니다.`n액세스가 거부되었습니다.") 0

Write-Host "[tlntadmn config]"
$r = ConvertFrom-TlntadmnConfig -Lines (Read-Fixture 'tlntadmn_config_en-US.txt')
Assert-Equal "en-US value" $r.Value 'NTLM, Password'
Assert-Equal "en-US methods" ($r.Methods -join '|') 'NTLM|Password'
$r = ConvertFrom-TlntadmnConfig -Lines (Read-Fixture 'tlntadmn_config_ko-KR.txt')
Assert-Equal "ko-KR methods" ($r.Methods -join '|') 'NTLM|Password'
$r = ConvertFrom-TlntadmnConfig -Lines (Read-Fixture 'tlntadmn_config_ntlm-aligned.txt')
Assert-Equal "space-aligned NTLM only" ($r.Methods -join '|') 'NTLM'
Assert-Equal "no auth line -> null" ($null -eq (ConvertFrom-TlntadmnConfig -Lines @('State : Running'))) $true

if ($script:fail -gt 0) { Write-Host "locale parse tests: $script:fail FAILED"; exit 1 }
Write-Host "locale parse tests: all passed"
exit 0
