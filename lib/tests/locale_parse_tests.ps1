# lib/tests/locale_parse_tests.ps1 — 로캘 의존 명령 출력 파싱 단위 테스트(1.5.0 C6, KNOWN_ISSUES L-02)
# 대상: lib/Common.psm1 의 ConvertFrom-AuditPolBackup(W-40) / Get-BcdEditEntryCount(PC-08) / ConvertFrom-TlntadmnConfig(W-34).
#       + 외부 명령 없이 확인하는 판정 헬퍼 Test-SmbDefaultShare(A7 W-16/PC-04) / Select-KnownItemCodes(C2 -Items 검증).
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

# 아래 둘은 로캘 파싱은 아니지만 외부 명령 없이 단위로 확인할 수 있는 Common.psm1 판정 헬퍼라 같은 CI 단계에서 돌린다.
Write-Host "[기본 관리 공유 판별 - A7 W-16/PC-04]"
# Special 값은 한글 Windows 11 의 Get-SmbShare 실측(ADMIN$/C$/IPC$ = True). 사용자 숨김 공유(Data$)는 Special=False.
$mk = { param($n, $sp) [PSCustomObject]@{ Name = $n; Special = $sp } }
Assert-Equal "ADMIN$ special" (Test-SmbDefaultShare -Share (& $mk 'ADMIN$' $true)) $true
Assert-Equal "C$ special" (Test-SmbDefaultShare -Share (& $mk 'C$' $true)) $true
Assert-Equal "IPC$ special" (Test-SmbDefaultShare -Share (& $mk 'IPC$' $true)) $true
Assert-Equal "print$ (Special=False)" (Test-SmbDefaultShare -Share (& $mk 'print$' $false)) $true
Assert-Equal "user hidden Data$" (Test-SmbDefaultShare -Share (& $mk 'Data$' $false)) $false
Assert-Equal "user hidden D$ (not special)" (Test-SmbDefaultShare -Share (& $mk 'D$' $false)) $false
Assert-Equal "normal share" (Test-SmbDefaultShare -Share (& $mk 'share' $false)) $false
Assert-Equal "no Special prop: C$" (Test-SmbDefaultShare -Share ([PSCustomObject]@{ Name = 'C$' })) $true
Assert-Equal "no Special prop: Data$" (Test-SmbDefaultShare -Share ([PSCustomObject]@{ Name = 'Data$' })) $false

Write-Host "[-Items 코드 검증 - C2]"
$known = @('PC-01', 'PC-02', 'PC-18')
$WarningPreference = 'SilentlyContinue'
Assert-Equal "known codes" ((Select-KnownItemCodes -Codes @('PC-01', 'PC-18') -KnownCodes $known) -join ',') 'PC-01,PC-18'
Assert-Equal "case-insensitive -> guide spelling" ((Select-KnownItemCodes -Codes @(' pc-02 ') -KnownCodes $known) -join ',') 'PC-02'
Assert-Equal "path traversal dropped" ((Select-KnownItemCodes -Codes @('..\..\probe', 'PC-01', '../x', 'PC-01\..\..\y') -KnownCodes $known) -join ',') 'PC-01'
Assert-Equal "wildcard not expanded" (@(Select-KnownItemCodes -Codes @('PC-*', '*') -KnownCodes $known).Count) 0
Assert-Equal "all unknown -> empty" (@(Select-KnownItemCodes -Codes @('..\..\probe') -KnownCodes $known).Count) 0
Assert-Equal "duplicates once" ((Select-KnownItemCodes -Codes @('PC-01', 'pc-01') -KnownCodes $known) -join ',') 'PC-01'
$WarningPreference = 'Continue'

Write-Host "[W-40 디렉터리 서비스 액세스 - A10]"
# 비 DC(한글 Windows 11)에도 하위 범주가 백업에 있다 - 실측값 0(감사 안 함)
$m = ConvertFrom-AuditPolBackup -Lines (Read-Fixture "auditpol_backup_ko-KR.csv")
Assert-Equal "ko-KR Directory Service Access present" $m['{0CCE923B-69AE-11D9-BED3-505054503030}'] 0

if ($script:fail -gt 0) { Write-Host "locale parse tests: $script:fail FAILED"; exit 1 }
Write-Host "locale parse tests: all passed"
exit 0
