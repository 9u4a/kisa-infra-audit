# 03_web/tests/fixtures/apply_iis.ps1 -Mode <vuln|hardened>
# GitHub Actions windows-latest(휘발성 Windows Server VM)에서만 실행한다 - IIS 설정·파일을 실제로 바꾸고
# 되돌리지 않는다. 로컬 개발자 PC에서는 절대 실행하지 말 것.
# 명시적으로 vuln/hardened 를 가르는 항목:
#   WEB-04 디렉터리 브라우징(Default Web Site), WEB-18 WebDAV 저작(authoring), WEB-12 사이트 루트의 정션
# 나머지 항목은 러너에 설치한 IIS 의 기본값을 반영한다(expected_iis_<mode>.json 은 실측값을 고정한 것).
param(
    [Parameter(Mandatory = $true)][ValidateSet("vuln", "hardened")][string]$Mode
)
$ErrorActionPreference = "Stop"
Import-Module WebAdministration

$site = "Default Web Site"
$vuln = ($Mode -eq "vuln")

Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $site -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $vuln
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Location $site -Filter "system.webServer/webdav/authoring" -Name "enabled" -Value $vuln

$root = [System.Environment]::ExpandEnvironmentVariables((Get-Website -Name $site).physicalPath)
$link = Join-Path $root "kisa_link"
$target = Join-Path $env:TEMP "kisa_link_target"
if ($vuln) {
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$target" | Out-Null }
} elseif (Test-Path $link) {
    # 정션은 링크만 지운다(rmdir) - Remove-Item -Recurse 는 PS 5.1 에서 대상 내용까지 지울 수 있다
    cmd /c rmdir "$link" | Out-Null
}
Write-Host "IIS 픽스처 적용: $Mode"
