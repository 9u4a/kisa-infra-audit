# lib/tests/fix_restore_tests.ps1 - G-07(실환경 VM 검증)에서 찾은 조치·원복 결함의 회귀 단위 테스트(PowerShell 쪽)
# 1) Get-FixSecPolicyRestoreLines: 전체 원복이 보안 정책 스냅샷을 통째로 다시 넣어 DC 의 NullSessionPipes(첫 원소가 빈 다중 문자열)를
#    비우고 한글 Win11 의 지역화 계정명("제한된 서비스\모든 제한된 서비스")을 SeServiceLogonRight 에서 뺐다 → 바꾼 키만 되돌리는지
# 2) Get-FixBackupFileName: IIS FTP 설정 필터 백업 이름이 MAX_PATH(260자)를 넘어 W-23 백업이 실패했다 → 긴 이름을 줄이는지
# 시스템을 바꾸지 않는다(임시 폴더의 가짜 스냅샷만 읽는다). pwsh 7(ubuntu)·Windows PowerShell 5.1 모두에서 돈다.
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Import-Module (Join-Path $Repo "lib/Common.psm1") -Force

$script:fail = 0; $script:pass = 0
function Assert-True([string]$Name, [bool]$Cond, [string]$Info = "") {
    if ($Cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $Name $Info" }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "kisa_restore_test_$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # ---- 1) 보안 정책 원복 INF ----
    $snap = Join-Path $tmp "secedit-snapshot.inf"
    # secedit /export 와 같은 UTF-16LE. DC 기본 NullSessionPipes 와 한글 지역화 계정명을 그대로 넣는다(G-07 실측 값)
    @('[Unicode]', 'Unicode=yes', '[System Access]', 'LockoutBadCount = 0', 'MinimumPasswordLength = 0',
        '[Event Audit]', 'AuditSystemEvents = 0',
        '[Registry Values]', 'MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\NullSessionPipes=7,,netlogon,samr,lsarpc',
        '[Privilege Rights]', 'SeServiceLogonRight = *S-1-5-80-0,제한된 서비스\모든 제한된 서비스', 'SeInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-545',
        '[Version]', 'signature="$CHICAGO$"', 'Revision=1') | Set-Content -Path $snap -Encoding Unicode
    $keys = Join-Path $tmp "changed-keys.txt"
    @("W-04`tSystem Access`tLockoutBadCount", "W-08`tSystem Access`tLockoutDuration", "W-11`tPrivilege Rights`tSeInteractiveLogonRight",
        "W-99`tPrivilege Rights`tSeDenyNetworkLogonRight") | Set-Content -Path $keys -Encoding UTF8

    $l = Get-FixSecPolicyRestoreLines -SnapshotFile $snap -KeyLog $keys   # 배열 하나로 돌려준다(return , $lines)
    $txt = $l -join "`n"
    Assert-True "바꾼 키: LockoutBadCount 를 스냅샷 값으로" ($l -contains "LockoutBadCount = 0") $txt
    Assert-True "바꾼 키: SeInteractiveLogonRight 를 스냅샷 값으로" ($l -contains "SeInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-545") $txt
    Assert-True "스냅샷에 없던 사용자 권한은 비움" ($l -contains "SeDenyNetworkLogonRight = ") $txt
    Assert-True "스냅샷에 없던 System Access 키는 쓰지 않음" ($txt -notmatch 'LockoutDuration') $txt
    Assert-True "안 바꾼 키(MinimumPasswordLength)는 쓰지 않음" ($txt -notmatch 'MinimumPasswordLength') $txt
    Assert-True "안 바꾼 지역화 계정명 권한(SeServiceLogonRight)은 쓰지 않음" ($txt -notmatch 'SeServiceLogonRight') $txt
    Assert-True "[Registry Values](NullSessionPipes)는 쓰지 않음" ($txt -notmatch 'Registry Values|NullSessionPipes') $txt
    Assert-True "안 바꾼 섹션([Event Audit])은 쓰지 않음" ($txt -notmatch 'Event Audit') $txt
    Assert-True "INF 머리·꼬리" ($l[0] -eq "[Unicode]" -and $l[-1] -eq "Revision=1") $txt

    # changed-keys.txt 가 없는 예전 백업: [Registry Values] 만 빼고 전체
    $l2 = Get-FixSecPolicyRestoreLines -SnapshotFile $snap -KeyLog (Join-Path $tmp "none.txt")
    $txt2 = $l2 -join "`n"
    Assert-True "예전 백업: [Registry Values] 제외" ($txt2 -notmatch 'NullSessionPipes') $txt2
    Assert-True "예전 백업: 나머지 섹션은 그대로" ($l2 -contains "MinimumPasswordLength = 0" -and $l2 -contains "AuditSystemEvents = 0") $txt2

    # ---- 2) 백업 파일 이름 ----
    $short = Get-FixBackupFileName -Raw "HKLM:\SOFTWARE\X--Y"
    Assert-True "짧은 이름은 문자 치환만" ($short -eq "HKLM__SOFTWARE_X--Y") $short
    $long = "MACHINE/WEBROOT/APPHOST----system.applicationHost/sites/site[@name='kisa_ftp_inherit']/ftpServer/security/authentication/anonymousAuthentication--enabled"
    $a = Get-FixBackupFileName -Raw $long
    Assert-True "긴 이름은 60자 이하" ($a.Length -le 60) "$($a.Length): $a"
    Assert-True "긴 이름은 같은 입력에 같은 결과(재백업 시 첫 백업 보존)" ($a -eq (Get-FixBackupFileName -Raw $long)) $a
    $b = Get-FixBackupFileName -Raw ($long -replace 'kisa_ftp_inherit', 'kisa_ftp_explicit')
    Assert-True "앞부분이 같은 다른 자원은 다른 이름" ($a -ne $b) "$a / $b"
    Assert-True "파일 이름에 쓸 수 없는 문자 없음" ($a -notmatch '[\\/:*?"<>|\[\]@=]') $a
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

if ($script:fail -gt 0) { Write-Host "FAIL: fix_restore_tests ($($script:fail) 실패 / $($script:pass) 통과)"; exit 1 }
Write-Host "PASS: fix_restore_tests ($($script:pass) 검사)"
exit 0
