# 03_web/tests/fixtures/apply_iis.ps1 -Mode <vuln|hardened>
# GitHub Actions windows-latest(휘발성 Windows Server VM)에서만 실행한다 - IIS 설정·파일을 실제로 바꾸고
# 되돌리지 않는다. 로컬 개발자 PC에서는 절대 실행하지 말 것.
# 명시적으로 vuln/hardened 를 가르는 항목:
#   WEB-04 디렉터리 브라우징(Default Web Site), WEB-18 WebDAV 저작(authoring), WEB-12 사이트 루트의 정션
# 나머지 항목은 러너에 설치한 IIS 의 기본값을 반영한다(expected_iis_<mode>.json 은 실측값을 고정한 것).
# -FixCases(조치 안전 검사 전용, vuln 과 함께 - run_tests_iis.ps1 의 기대값에는 쓰지 않는다): F-R3 재현 케이스를 추가한다.
#   사이트 루트: 리스팅·WebDAV 저작을 끔(하위 경로만 취약하게 - 루트만 고치는 조치를 가려내기 위함)
#   하위 application(/kisa_fixapp): 리스팅·WebDAV 저작 켬, errorMode=Detailed(WEB-04/18/22 - 루트만 고치는 조치로는 VULN 이 남음)
#   하위 virtual directory(/kisa_fixvdir): 리스팅 켬(WEB-04)
#   사이트 재정의: Default Web Site 의 removeServerHeader=false(WEB-16 - 서버 전역만 고치는 조치로는 VULN 이 남음)
# 되돌리지 않는다(휘발성 러너 전용 - CI 에서는 진단 회귀(vuln→hardened)가 끝난 뒤 조치 안전 검사 직전에만 쓴다).
# 의도적으로 정리하지 않는다: 이후 workflow 단계(02_windows 조치 안전)의 W-33(실제 HTTP Server 헤더)이 이 사이트 재정의
# (removeServerHeader=false)를 그대로 보게 되어, W-33 조치가 전역뿐 아니라 사이트 재정의까지 고치는지도 검증된다(CI 실측으로
# 드러난 결함). 03_web 조치 안전 검사는 끝에 원복하므로 이 시점 상태(픽스처 vuln + 재현 케이스)로 돌아간다.
param(
    [Parameter(Mandatory = $true)][ValidateSet("vuln", "hardened")][string]$Mode,
    [switch]$FixCases
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
$apphost = "MACHINE/WEBROOT/APPHOST"
$appName = "kisa_fixapp"; $vdirName = "kisa_fixvdir"
$caseRoot = Join-Path $env:SystemDrive "kisa_fixcase"
if ($FixCases) {
    if (-not $vuln) { throw "-FixCases 는 -Mode vuln 과 함께만 쓴다" }
    foreach ($d in @($appName, $vdirName)) { New-Item -ItemType Directory -Force -Path (Join-Path $caseRoot $d) | Out-Null }
    if (-not (Get-WebApplication -Site $site -Name $appName)) {
        New-WebApplication -Site $site -Name $appName -PhysicalPath (Join-Path $caseRoot $appName) -ApplicationPool "DefaultAppPool" | Out-Null
    }
    if (-not (Get-WebVirtualDirectory -Site $site -Name $vdirName)) {
        New-WebVirtualDirectory -Site $site -Name $vdirName -PhysicalPath (Join-Path $caseRoot $vdirName) | Out-Null
    }
    # 루트는 정상(꺼짐)으로 두고 하위 경로만 켠다. 첫 CI(run 40671991571)에서는 루트도 켜져 있어 하위 location 값이 상속값과
    # 같았고, 조치가 루트만 고쳐도 하위가 함께 정상이 되어(상속 또는 같은 값 기록 생략) 하위 경로 조치를 검증하지 못했다.
    Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $false
    Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/webdav/authoring" -Name "enabled" -Value $false
    # 하위 경로 자신의 설정(applicationHost.config <location path="사이트/하위">)으로 켠다 - 상속값(꺼짐)과 달라 명시 기록된다
    Set-WebConfigurationProperty -PSPath $apphost -Location "$site/$appName" -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $true
    Set-WebConfigurationProperty -PSPath $apphost -Location "$site/$appName" -Filter "system.webServer/webdav/authoring" -Name "enabled" -Value $true
    Set-WebConfigurationProperty -PSPath $apphost -Location "$site/$appName" -Filter "system.webServer/httpErrors" -Name "errorMode" -Value "Detailed"
    Set-WebConfigurationProperty -PSPath $apphost -Location "$site/$vdirName" -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $true
    # WEB-16 사이트 재정의: 상속값(전역 false)과 같은 값은 명시 기록되지 않을 수 있어(첫 CI 에서 재정의가 재현되지 않음) 전역을 잠시
    # true 로 바꾼 상태에서 사이트에 false 를 기록한 뒤 전역을 false(취약)로 되돌린다
    $rf = "system.webServer/security/requestFiltering"
    Set-WebConfigurationProperty -PSPath $apphost -Filter $rf -Name "removeServerHeader" -Value $true
    Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter $rf -Name "removeServerHeader" -Value $false
    Set-WebConfigurationProperty -PSPath $apphost -Filter $rf -Name "removeServerHeader" -Value $false
    $siteRsh = (Get-WebConfigurationProperty -PSPath "IIS:\Sites\$site" -Filter $rf -Name "removeServerHeader").Value
    Write-Host "  WEB-16 재현: 전역 false, 사이트 유효 값 $siteRsh (사이트 재정의 false 가 기록됐는지 - 조치가 전역만 바꾸면 사이트가 남아야 함)"
}
Write-Host "IIS 픽스처 적용: $Mode$(if ($FixCases) { ' + 조치 재현 케이스(F-R3)' })"
