# WEB-15 (상) 웹 서비스의 불필요한 스크립트 매핑 제거 [IIS] — 조치 [fix: param]
# 값: handlers=제거할 처리기 매핑 이름(쉼표 구분) - 진단 증적의 경로별 "스크립트 매핑" 목록에서 업무상 필요 없는 것(예: SSINC-shtml)
# 변경: IIS 사이트·하위 application/virtual directory 의 system.webServer/handlers 에서 지정 이름의 스크립트 매핑 제거(원복 불가)
# 원복: 불가 — 제거한 처리기 매핑은 자동으로 다시 등록하지 않음(필요 시 처리기 매핑에서 수동 재등록)
# 영향: 지정 매핑이 처리하던 확장자 요청이 즉시 처리되지 않음(404·정적 파일로 응답) — 그 확장자를 쓰는 앱 기능이 멈춤
# 가이드 조치 방법: 불필요한 스크립트 매핑 제거. 필요 여부는 운영 중인 애플리케이션에 달려 있어 사람이 판단한다(1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 어느 사이트 경로에든 그 이름의 "스크립트" 매핑(ISAPI/CGI/FastCGI/SSI 모듈 또는
# scriptProcessor)이 있음·중복 없음. 정적 파일·기본 처리기 등 스크립트 매핑이 아닌 것은 거부한다.

$names = @(Get-FixParam -Key "handlers")
if ($names.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 WEB-15.handlers 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
if (-not (Test-IisAvailable)) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "IIS 가 설치되어 있지 않아 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$scriptModules = "IsapiModule|CgiModule|FastCgiModule|ServerSideIncludeModule"
$found = @{}; $errs = @(); $seen = @{}
$Global:IisConfigQueryFailed = $false
$allPaths = @(foreach ($site in @(Get-IisSiteNames)) { Get-IisSiteConfigPaths -SiteName $site })
if ($Global:IisConfigQueryFailed) { $errs += "하위 경로 조회 실패: $($Global:IisConfigQueryError)" }
foreach ($cp in $allPaths) {
    try { $handlers = @(Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath $cp.PSPath -ErrorAction Stop) }
    catch { $errs += "$($cp.Label): handler mapping 조회 실패 $($_.Exception.Message)"; continue }
    foreach ($h in $handlers) {
        if ("$($h.modules)" -match $scriptModules -or -not [string]::IsNullOrEmpty("$($h.scriptProcessor)")) { $found["$($h.name)"] = $true }
    }
}
foreach ($n in $names) {
    if ($seen.ContainsKey($n)) { $errs += "${n}: 값에 두 번 나옴"; continue }
    $seen[$n] = $true
    if (-not $found.ContainsKey($n)) { $errs += "${n}: 사이트 경로의 스크립트 매핑(ISAPI/CGI/FastCGI/SSI) 중에 없음" }
}
$Global:IisConfigQueryFailed = $false
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

Register-FixNoRollback -Reason "IIS 에서 제거한 처리기 매핑($($names -join ', ')) - 필요 시 처리기 매핑에서 수동 재등록"
# 루트 먼저(Get-IisSiteConfigPaths 순서) - 루트에서 지운 상속 매핑은 하위에서 다시 읽을 때 없다. handlers 위임이 막혀 경로 쓰기가 실패하면
# applicationHost.config 의 <location path="site/app"> 에서 지운다(WEB-19 와 같은 방식)
$applied = @(); $failed = @()
foreach ($cp in $allPaths) {
    try { $handlers = @(Get-WebConfiguration -Filter "system.webServer/handlers/add" -PSPath $cp.PSPath -ErrorAction Stop) }
    catch { $failed += "$($cp.Label): 조회 실패 $($_.Exception.Message)"; continue }
    foreach ($h in @($handlers | Where-Object { $names -contains "$($_.name)" })) {
        try {
            Remove-WebConfigurationProperty -Filter "system.webServer/handlers" -PSPath $cp.PSPath -Name "." -AtElement @{ name = $h.name } -ErrorAction Stop
            $applied += "$($cp.Label)($($h.name))"
        } catch {
            $first = $_.Exception.Message
            try {
                Remove-WebConfigurationProperty -Filter "system.webServer/handlers" -PSPath "MACHINE/WEBROOT/APPHOST" -Location $cp.Label -Name "." -AtElement @{ name = $h.name } -ErrorAction Stop
                $applied += "$($cp.Label)($($h.name), applicationHost.config location)"
            } catch { $failed += "$($cp.Label)($($h.name)): $first / location: $($_.Exception.Message)" }
        }
    }
}
$Global:FixEvidence = ""
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "일부 처리기 매핑 제거 실패: $($failed -join ', ')"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "지정 처리기 매핑 제거: $($applied -join ', ')"
} else {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "지정 처리기 매핑을 어느 경로에서도 지우지 못함(검증 후 사라짐)"
}
