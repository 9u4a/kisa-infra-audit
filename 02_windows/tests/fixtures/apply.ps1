# 02_windows/tests/fixtures/apply.ps1 -Mode <vuln|hardened>
# GitHub Actions windows-latest(매 job마다 새로 생성되는 휘발성 VM)에서만 실행한다 - 실제
# 개발자 PC에서 이 스크립트를 돌리면 레지스트리가 실제로 바뀐다. W-15(개인키 사용 시 암호
# 입력)만 명시적으로 vuln/hardened를 가른다 - 기본값(레지스트리 키 없음)이 이미 VULN이라
# vuln 모드는 아무 것도 하지 않고, hardened만 명시적으로 설정한다.
param(
    [Parameter(Mandatory = $true)][ValidateSet("vuln", "hardened")][string]$Mode
)
$ErrorActionPreference = "Stop"

$keyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Protect"

if ($Mode -eq "hardened") {
    if (-not (Test-Path $keyPath)) { New-Item -Path $keyPath -Force | Out-Null }
    Set-ItemProperty -Path $keyPath -Name "ForceKeyProtection" -Value 2 -Type DWord
} else {
    if (Test-Path $keyPath) { Remove-ItemProperty -Path $keyPath -Name "ForceKeyProtection" -ErrorAction SilentlyContinue }
}
