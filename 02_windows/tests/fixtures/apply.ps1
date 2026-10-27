# 02_windows/tests/fixtures/apply.ps1 -Mode <vuln|hardened>
# GitHub Actions windows-latest(매 job마다 새로 생성되는 휘발성 VM)에서만 실행한다 - 실제
# 개발자 PC에서 이 스크립트를 돌리면 레지스트리·서비스가 실제로 바뀐다. 명시적으로 vuln/hardened 를
# 가르는 항목: W-15(개인키 사용 시 암호 입력 - 기본값이 이미 VULN 이라 hardened 만 설정),
# W-44(원격 레지스트리 서비스 - vuln 은 기동, hardened 는 중지).
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

# W-44(원격 레지스트리 서비스): 러너 이미지 기본 상태에 기대지 않고 명시적으로 만든다 - 이미지가
# windows-2025-vs2026 20261021 로 바뀌면서 기본 실행 상태가 달라져 기대값이 깨진 적이 있다(1.3.0 CI).
if ($Mode -eq "vuln") {
    # RemoteRegistry 는 유휴 시 스스로 멈추는(트리거 시작) 서비스라 진단 시점엔 이미 중지돼 W-44/PC-05 가 GOOD 으로
    # 흔들렸다 - 유휴 중지를 끄고 기동한다(hardened 에서 되돌림)
    if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters")) { New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters" | Out-Null }   # -Force 는 기존 키(ServiceDll)를 덮어쓴다
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters" -Name DisableIdleStop -Type DWord -Value 1
    Stop-Service -Name "RemoteRegistry" -Force -ErrorAction SilentlyContinue
    Set-Service -Name "RemoteRegistry" -StartupType Manual
    Start-Service -Name "RemoteRegistry"
} else {
    Stop-Service -Name "RemoteRegistry" -Force -ErrorAction SilentlyContinue
}
