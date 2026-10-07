# 07_pc/tests/fixtures/apply.ps1 -Mode <vuln|hardened>
# GitHub Actions windows-latest(매 job마다 새로 생성되는 휘발성 VM)에서만 실행한다. PC-12
# (Windows 자동 로그인)만 명시적으로 vuln/hardened를 가른다 - 기본값(레지스트리 키 없음)이
# 이미 GOOD이라 hardened 모드는 아무 것도 하지 않고, vuln만 명시적으로 설정한다.
param(
    [Parameter(Mandatory = $true)][ValidateSet("vuln", "hardened")][string]$Mode
)
$ErrorActionPreference = "Stop"

$keyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

if ($Mode -eq "vuln") {
    Set-ItemProperty -Path $keyPath -Name "AutoAdminLogon" -Value "1" -Type String
} else {
    Remove-ItemProperty -Path $keyPath -Name "AutoAdminLogon" -ErrorAction SilentlyContinue
}
