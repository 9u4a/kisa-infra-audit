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

# PC-05(불필요 서비스): 러너 이미지 기본값이나 같은 VM 에서 먼저 도는 02_windows 픽스처(W-44 가
# RemoteRegistry 를 끔)의 영향을 받지 않도록 상태를 명시한다 - vuln 은 RemoteRegistry 기동,
# hardened 는 checks/PC-05.ps1 의 점검 대상 서비스를 모두 중지.
if ($Mode -eq "vuln") {
    # RemoteRegistry 는 유휴 시 스스로 멈추는(트리거 시작) 서비스라 진단 시점엔 이미 중지돼 W-44/PC-05 가 GOOD 으로
    # 흔들렸다 - 유휴 중지를 끄고 기동한다(hardened 에서 되돌림)
    if (-not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters")) { New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters" | Out-Null }   # -Force 는 기존 키(ServiceDll)를 덮어쓴다
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteRegistry\Parameters" -Name DisableIdleStop -Type DWord -Value 1
    Stop-Service -Name "RemoteRegistry" -Force -ErrorAction SilentlyContinue
    Set-Service -Name "RemoteRegistry" -StartupType Manual
    Start-Service -Name "RemoteRegistry"
} else {
    foreach ($s in @("RemoteRegistry", "SSDPSRV", "upnphost", "WerSvc", "TapiSrv", "Fax")) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }
}
