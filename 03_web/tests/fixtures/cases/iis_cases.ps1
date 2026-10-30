# 03_web/tests/fixtures/cases/iis_cases.ps1 - IIS 항목별 판정 양방향 케이스 구현(cases.json 의 engine=iis 선언과 이름으로 짝지음)
# GitHub Actions windows-latest(휘발성 VM)에서만 실행한다 - IIS 설정·ACL 을 실제로 바꾼다. 로컬 PC 에서 실행 금지.
# 형식은 lib/tests/win_case_runner.ps1 참고. 기대 판정(cases.json expect)은 guide.json 판단기준에서 정한 것이다(도구 출력 아님).
# 정리: 설정은 applicationHost.config 와 사이트 루트 web.config 를 준비 직전 사본으로 되돌리고(Save-CaseConfig/Restore-CaseConfig),
#       ACL 은 icacls /save → /restore 로 되돌린다. 정리 후 Probe 가 준비 전과 같은지 러너가 비교한다.

$IisCasePrelude = @'
Import-Module WebAdministration
$site = 'Default Web Site'
$apphost = 'MACHINE/WEBROOT/APPHOST'
$apphostFile = Join-Path $env:windir 'system32\inetsrv\config\applicationHost.config'
$siteRoot = [System.Environment]::ExpandEnvironmentVariables((Get-Website -Name $site).physicalPath)
$caseTmp = Join-Path $env:TEMP 'kisa_iis_case'
function Save-CaseConfig {
    New-Item -ItemType Directory -Force -Path $caseTmp | Out-Null
    Copy-Item -LiteralPath $apphostFile -Destination (Join-Path $caseTmp 'applicationHost.config') -Force
    $wc = Join-Path $siteRoot 'web.config'
    if (Test-Path -LiteralPath $wc) { Copy-Item -LiteralPath $wc -Destination (Join-Path $caseTmp 'site.web.config') -Force }
    else { Remove-Item -Force (Join-Path $caseTmp 'site.web.config') -ErrorAction SilentlyContinue }
    Set-Content -Path (Join-Path $caseTmp 'siteRoot.txt') -Value $siteRoot -Encoding UTF8
}
function Restore-CaseConfig {
    $saved = Join-Path $caseTmp 'applicationHost.config'
    if (-not (Test-Path -LiteralPath $saved)) { return }
    # 사이트 경로를 바꾸는 케이스(WEB-11)가 있어 준비 시점의 사이트 루트를 쓴다
    $root = (Get-Content -Raw -Path (Join-Path $caseTmp 'siteRoot.txt')).Trim()
    Copy-Item -LiteralPath $saved -Destination $apphostFile -Force
    $wc = Join-Path $root 'web.config'
    $savedWc = Join-Path $caseTmp 'site.web.config'
    if (Test-Path -LiteralPath $savedWc) { Copy-Item -LiteralPath $savedWc -Destination $wc -Force }
    elseif (Test-Path -LiteralPath $wc) { Remove-Item -Force -LiteralPath $wc }
    Remove-Item -Force $saved
    Start-Sleep -Seconds 1
}
function Save-CaseAcl([string]$Path, [string]$Tag) {
    New-Item -ItemType Directory -Force -Path $caseTmp | Out-Null
    $f = Join-Path $caseTmp "acl_$Tag.txt"
    & icacls $Path /save $f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /save failed: $Path" }
}
function Restore-CaseAcl([string]$Path, [string]$Tag) {
    $f = Join-Path $caseTmp "acl_$Tag.txt"
    if (-not (Test-Path $f)) { return }
    & icacls (Split-Path -Parent $Path) /restore $f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls /restore failed: $Path" }
    Remove-Item -Force $f
}
function Get-CaseAce([string]$Path, [string]$Sid, [int64]$Mask = -1) {
    # 지정 SID 의 명시적·상속 Allow ACE 중 권한 비트가 Mask 와 겹치는 것의 수
    $acl = Get-Acl -LiteralPath $Path
    @($acl.Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq $Sid -and
        ($Mask -eq -1 -or (([int64]$_.FileSystemRights) -band $Mask) -ne 0)
    }).Count
}
function Get-SiteVal([string]$Filter, [string]$Name, [string]$Path = "IIS:\Sites\$site") {
    $v = Get-WebConfigurationProperty -PSPath $Path -Filter $Filter -Name $Name -ErrorAction Stop
    if ($null -ne $v -and $v.PSObject.Properties.Name -contains 'Value') { return "$($v.Value)" }
    return "$v"
}
function Get-SsiHandlerCount {
    @(Get-WebConfiguration -Filter 'system.webServer/handlers/add' -PSPath "IIS:\Sites\$site" -ErrorAction Stop |
        Where-Object { $p = $_.path; @('.htr', '.idc', '.stm', '.shtm', '.shtml', '.printer', '.htw', '.ida', '.idq') | Where-Object { $p -ilike "*$_" } }).Count
}
$writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
$samPath = Join-Path $env:SystemRoot 'system32\config\SAM'
$logDir = Join-Path $env:SystemDrive 'inetpub\logs\LogFiles'
$msadc = Join-Path $env:SystemDrive 'Program Files\Common Files\System\msadc'
function Get-SampleState {
    $s = foreach ($p in @('inetpub\iissamples', 'inetpub\AdminScripts', 'inetpub\wwwroot\iishelp')) { "$((Split-Path -Leaf $p).ToLower())=$(Test-Path -LiteralPath (Join-Path $env:SystemDrive $p))" }
    $m = "msadc=$(Test-Path -LiteralPath $msadc)"
    if (Test-Path -LiteralPath $msadc) { $acl = Get-Acl -LiteralPath $msadc; $m += " owner=$($acl.Owner) dacl=$($acl.GetSecurityDescriptorSddlForm('Access')) files=$(@(Get-ChildItem -LiteralPath $msadc -Recurse -Force).Count)" }
    return "$($s -join ' ') $m"
}
function Hide-Msadc {
    # 이름만 바꿔 치운다(소유자·DACL 은 그대로). 이름 변경이 거부되면 소유권을 가져와 바꾸고 정리 때 DACL·소유자를 되돌린다
    if (-not (Test-Path -LiteralPath $msadc)) { return }
    try { Rename-Item -LiteralPath $msadc -NewName 'msadc.kisa_case' -ErrorAction Stop; return } catch { Write-Output "rename denied, taking ownership: $($_.Exception.Message)" }
    & icacls $msadc /save (Join-Path $caseTmp 'msadc_acl.txt') /T /C | Out-Null
    if ($LASTEXITCODE) { throw 'icacls /save msadc failed' }
    & takeown /F $msadc /R /D Y | Out-Null
    & icacls $msadc /grant '*S-1-5-32-544:(OI)(CI)F' /T /C | Out-Null
    Rename-Item -LiteralPath $msadc -NewName 'msadc.kisa_case' -ErrorAction Stop
}
function Show-Msadc {
    $moved = "$msadc.kisa_case"
    if (Test-Path -LiteralPath $moved) { Rename-Item -LiteralPath $moved -NewName 'msadc' -ErrorAction Stop }
    $a = Join-Path $caseTmp 'msadc_acl.txt'
    if (Test-Path $a) {
        & icacls (Split-Path -Parent $msadc) /restore $a /C | Out-Null
        if ($LASTEXITCODE) { throw 'icacls /restore msadc failed' }
        & icacls $msadc /setowner 'NT SERVICE\TrustedInstaller' /T /C | Out-Null
        if ($LASTEXITCODE) { throw 'icacls /setowner msadc failed' }
        Remove-Item -Force $a
    }
}
'@

$IisCases = @{
    # WEB-03 취약: 비밀번호 파일(SAM)에 일반 사용자(Users) 읽기 허용 - HiveNightmare(CVE-2021-36934) 상태
    "sam-users-read" = @{
        Probe = 'Write-Output ("sam_users_allow=" + (Get-CaseAce $samPath "S-1-5-32-545"))'
        Setup = 'Save-CaseAcl $samPath "sam"; & icacls $samPath /grant "*S-1-5-32-545:(R)" | Out-Null; if ($LASTEXITCODE) { throw "icacls grant failed" }'
        Cleanup = 'Restore-CaseAcl $samPath "sam"'
        Want = '^sam_users_allow=[1-9]'; Fix = $true
    }
    # WEB-05 취약: 목록에 없는 CGI 실행 허용(notListedCgisAllowed=true)
    "notlisted-cgi-allowed" = @{
        Probe = 'Write-Output ("cgi=" + (Get-SiteVal "system.webServer/security/isapiCgiRestriction" "notListedCgisAllowed" $apphost) + " isapi=" + (Get-SiteVal "system.webServer/security/isapiCgiRestriction" "notListedIsapisAllowed" $apphost))'
        Setup = 'Save-CaseConfig; Set-WebConfigurationProperty -PSPath $apphost -Filter "system.webServer/security/isapiCgiRestriction" -Name notListedCgisAllowed -Value $true'
        Cleanup = 'Restore-CaseConfig'
        Want = '^cgi=True'; Fix = $true
    }
    # WEB-06 취약: 상위 디렉터리 접근(asp enableParentPaths=true)
    "asp-parent-paths" = @{
        Probe = 'Write-Output ("parentPaths=" + (Get-SiteVal "system.webServer/asp" "enableParentPaths"))'
        Setup = 'Save-CaseConfig; Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/asp" -Name enableParentPaths -Value $true'
        Cleanup = 'Restore-CaseConfig'
        Want = '^parentPaths=True$'; Fix = $true
    }
    # WEB-08 취약: 업로드 용량 사실상 무제한(maxAllowedContentLength=4294967295)
    "upload-unlimited" = @{
        Probe = 'Write-Output ("maxAllowedContentLength=" + (Get-SiteVal "system.webServer/security/requestFiltering/requestLimits" "maxAllowedContentLength"))'
        Setup = 'Save-CaseConfig; Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/security/requestFiltering/requestLimits" -Name maxAllowedContentLength -Value 4294967295'
        Cleanup = 'Restore-CaseConfig'
        Want = '^maxAllowedContentLength=4294967295$'; Fix = $true
    }
    # WEB-09 취약: 애플리케이션 풀이 LocalSystem(관리자 권한)으로 구동
    "apppool-localsystem" = @{
        Probe = '$p = (Get-Website -Name $site).applicationPool; Write-Output ("pool=$p identity=" + (Get-ItemProperty "IIS:\AppPools\$p" -Name processModel.identityType))'
        Setup = 'Save-CaseConfig; $p = (Get-Website -Name $site).applicationPool; Set-ItemProperty "IIS:\AppPools\$p" -Name processModel.identityType -Value LocalSystem'
        Cleanup = 'Restore-CaseConfig'
        Want = 'identity=LocalSystem$'; Fix = $true
    }
    # WEB-10 취약: ARR 프록시 활성(workflow 가 ARR 을 설치해 둔다)
    "arr-proxy-enabled" = @{
        Probe = '$m = [bool](Get-WebConfiguration -Filter "system.webServer/globalModules/add[@name=''ApplicationRequestRouting'']" -PSPath $apphost); $e = if ($m) { (Get-WebConfiguration -Filter "system.webServer/proxy" -PSPath $apphost -ErrorAction Stop).enabled } else { "-" }; Write-Output "arr=$m proxy=$e"'
        Setup = '$m = [bool](Get-WebConfiguration -Filter "system.webServer/globalModules/add[@name=''ApplicationRequestRouting'']" -PSPath $apphost); if (-not $m) { throw "ARR(ApplicationRequestRouting) 모듈이 설치되어 있지 않음 - workflow 의 ARR 설치 단계 확인" }; Save-CaseConfig; Set-WebConfigurationProperty -PSPath $apphost -Filter "system.webServer/proxy" -Name enabled -Value $true'
        Cleanup = 'Restore-CaseConfig'
        Want = '^arr=True proxy=True$'; Fix = $true
    }
    # WEB-11 양호: 사이트 경로를 기본 설치 경로(inetpub\wwwroot)와 분리된 전용 경로로 지정
    "separate-site-root" = @{
        Probe = 'Write-Output ("physicalPath=" + (Get-Website -Name $site).physicalPath)'
        Setup = 'Save-CaseConfig; New-Item -ItemType Directory -Force -Path "C:\kisa_case_webroot" | Out-Null; Set-ItemProperty "IIS:\Sites\$site" -Name physicalPath -Value "C:\kisa_case_webroot"'
        Cleanup = 'Restore-CaseConfig; Remove-Item -Recurse -Force "C:\kisa_case_webroot" -ErrorAction SilentlyContinue'
        Want = '^physicalPath=C:\\kisa_case_webroot$'
    }
    # WEB-13 취약: hiddenSegments 에서 web.config 제거(설정 파일 직접 다운로드 노출)
    "hidden-webconfig-removed" = @{
        Probe = '$s = @(Get-WebConfiguration -Filter "system.webServer/security/requestFiltering/hiddenSegments/add" -PSPath "IIS:\Sites\$site" -ErrorAction Stop | ForEach-Object { $_.segment }); Write-Output ("webconfig_hidden=" + ($s -contains "web.config"))'
        Setup = 'Save-CaseConfig; Remove-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/security/requestFiltering/hiddenSegments" -Name "." -AtElement @{ segment = "web.config" }'
        Cleanup = 'Restore-CaseConfig'
        Want = '^webconfig_hidden=False$'; Fix = $true; NoRollback = $true
    }
    # WEB-14 취약: 사이트 경로에 일반 사용자(Users) 수정 권한
    "siteroot-users-modify" = @{
        Probe = 'Write-Output ("siteroot_users_write=" + (Get-CaseAce $siteRoot "S-1-5-32-545" $writeMask))'
        Setup = 'Save-CaseAcl $siteRoot "siteroot"; & icacls $siteRoot /grant "*S-1-5-32-545:(OI)(CI)(M)" | Out-Null; if ($LASTEXITCODE) { throw "icacls grant failed" }'
        Cleanup = 'Restore-CaseAcl $siteRoot "siteroot"'
        Want = '^siteroot_users_write=[1-9]'; Fix = $true
    }
    # WEB-15/WEB-19 양호: SSI(.stm/.shtm/.shtml) 등 불필요 스크립트 매핑 제거(서버 전역 handlers 에서 SSINC-* 삭제)
    "no-ssi-handlers" = @{
        Probe = 'Write-Output ("danger_handlers=" + (Get-SsiHandlerCount))'
        Setup = 'Save-CaseConfig; foreach ($h in @(Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath $apphost | Where-Object { $_.modules -eq "ServerSideIncludeModule" })) { Remove-WebConfigurationProperty -PSPath $apphost -Filter "system.webServer/handlers" -Name "." -AtElement @{ name = $h.name } }'
        Cleanup = 'Restore-CaseConfig'
        Want = '^danger_handlers=0$'
    }
    # WEB-16 양호: Server 헤더 제거(removeServerHeader=true, 사이트 재정의 없음)
    "remove-server-header" = @{
        Probe = 'Write-Output ("global=" + (Get-SiteVal "system.webServer/security/requestFiltering" "removeServerHeader" $apphost) + " site=" + (Get-SiteVal "system.webServer/security/requestFiltering" "removeServerHeader"))'
        Setup = 'Save-CaseConfig; Set-WebConfigurationProperty -PSPath $apphost -Filter "system.webServer/security/requestFiltering" -Name removeServerHeader -Value $true'
        Cleanup = 'Restore-CaseConfig'
        Want = '^global=True site=True$'
    }
    # WEB-20 양호: https 바인딩(SSL/TLS) 구성
    "https-binding" = @{
        Probe = 'Write-Output ("https_bindings=" + @(Get-WebBinding -Name $site -Protocol https).Count)'
        Setup = 'Save-CaseConfig; New-WebBinding -Name $site -Protocol https -Port 44300 -IPAddress "*"'
        Cleanup = 'Restore-CaseConfig'
        Want = '^https_bindings=1$'
    }
    # WEB-21 양호: https 바인딩 + SSL 필수(sslFlags=Ssl) - 평문 HTTP 접근 차단
    "https-require-ssl" = @{
        Probe = 'Write-Output ("https_bindings=" + @(Get-WebBinding -Name $site -Protocol https).Count + " sslFlags=" + (Get-SiteVal "system.webServer/security/access" "sslFlags"))'
        Setup = 'Save-CaseConfig; New-WebBinding -Name $site -Protocol https -Port 44300 -IPAddress "*"; Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/security/access" -Name sslFlags -Value "Ssl"'
        Cleanup = 'Restore-CaseConfig'
        Want = '^https_bindings=1 sslFlags=Ssl$'
    }
    # WEB-21 취약: https 바인딩은 있으나 HTTP 리디렉션/SSL 필수 없음 - 조치(sslFlags=Ssl) 대상
    "https-without-redirect" = @{
        Probe = 'Write-Output ("https_bindings=" + @(Get-WebBinding -Name $site -Protocol https).Count + " sslFlags=" + (Get-SiteVal "system.webServer/security/access" "sslFlags"))'
        Setup = 'Save-CaseConfig; New-WebBinding -Name $site -Protocol https -Port 44300 -IPAddress "*"'
        Cleanup = 'Restore-CaseConfig'
        Want = '^https_bindings=1 sslFlags=(None|0)?$'; Fix = $true
    }
    # WEB-22 취약: 원격에도 상세 오류 노출(errorMode=Detailed)
    "errormode-detailed" = @{
        Probe = 'Write-Output ("errorMode=" + (Get-SiteVal "system.webServer/httpErrors" "errorMode"))'
        Setup = 'Save-CaseConfig; Set-WebConfigurationProperty -PSPath $apphost -Location $site -Filter "system.webServer/httpErrors" -Name errorMode -Value Detailed'
        Cleanup = 'Restore-CaseConfig'
        Want = '^errorMode=Detailed$'; Fix = $true
    }
    # WEB-26 취약: 로그 디렉터리에 일반 사용자(Users) 읽기 허용. 새로 설치한 IIS 는 첫 요청 전까지 LogFiles 가 없을 수 있어 만든다
    "logdir-users-read" = @{
        Probe = 'if (Test-Path -LiteralPath $logDir) { Write-Output ("logdir_users_allow=" + (Get-CaseAce $logDir "S-1-5-32-545")) } else { Write-Output "logdir=absent" }'
        Setup = 'if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null; Set-Content -Path (Join-Path $caseTmp "logdir_created.txt") -Value 1 } else { Remove-Item -Force (Join-Path $caseTmp "logdir_created.txt") -ErrorAction SilentlyContinue }; Save-CaseAcl $logDir "logdir"; & icacls $logDir /grant "*S-1-5-32-545:(OI)(CI)(RX)" | Out-Null; if ($LASTEXITCODE) { throw "icacls grant failed" }'
        Cleanup = 'Restore-CaseAcl $logDir "logdir"; if (Test-Path (Join-Path $caseTmp "logdir_created.txt")) { Remove-Item -Recurse -Force -LiteralPath $logDir; Remove-Item -Force (Join-Path $caseTmp "logdir_created.txt") }'
        Want = '^logdir_users_allow=[1-9]'; Fix = $true
    }
    # WEB-07 양호: 기본 샘플/관리 스크립트 경로가 없음 - 러너(Windows Server)에는 MDAC 의 msadc 가 기본으로 있어 잠시 이름을 바꿔 둔다
    "no-default-samples" = @{
        Probe = 'Write-Output (Get-SampleState)'
        Setup = 'Hide-Msadc'
        Cleanup = 'Show-Msadc'
        Want = '^iissamples=False adminscripts=False iishelp=False msadc=False$'
    }
    # WEB-07 취약: 기본 샘플 경로(iissamples)가 존재 - 조치(경로 백업 후 제거) → 원복 검증. 조치는 TrustedInstaller 소유 msadc 를
    # 지우지 않으므로(C-WEB07) 조치 검증이 가능하도록 msadc 는 치워 두고 iissamples 만 취약 상태로 만든다
    "iissamples-present" = @{
        Probe = 'Write-Output (Get-SampleState)'
        Setup = 'Hide-Msadc; New-Item -ItemType Directory -Force -Path (Join-Path $env:SystemDrive "inetpub\iissamples") | Out-Null; Set-Content -Path (Join-Path $env:SystemDrive "inetpub\iissamples\default.htm") -Value "kisa case"'
        Cleanup = 'Remove-Item -Recurse -Force -LiteralPath (Join-Path $env:SystemDrive "inetpub\iissamples") -ErrorAction SilentlyContinue; Show-Msadc'
        Want = '^iissamples=True adminscripts=False iishelp=False msadc=False$'; Fix = $true
    }
}
