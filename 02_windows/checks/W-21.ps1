# W-21 (상) 암호화되지 않는 FTP 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = FTP 미사용 또는 Secure FTP 사용 / 취약 = 평문 FTP 사용
# F-W21(1.4.0): 예전에는 FTP 서비스가 구동 중이면 SSL 정책과 무관하게 VULN 이었다(가이드 양호 조건 "Secure FTP 사용" 미반영 -
# 양방향 케이스로 확인). 등록된 FTP 사이트가 1개 이상이고 모든 사이트의 제어·데이터 채널 정책이 SSL 필수(SslRequire)면 양호.
# 사이트에 명시 값이 없으면 IIS 는 siteDefaults 값을 적용한다(W-23 과 같은 방식으로 유효 값을 읽는다).

$svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
if (-not $svc) {
    return New-CheckResult -Code "W-21" -Status "GOOD" -Detail "FTP 서비스(Microsoft FTP Service)가 설치되어 있지 않음"
}

if ($svc.Status -ne "Running") {
    return New-CheckResult -Code "W-21" -Status "GOOD" -Detail "FTP 서비스가 설치되어 있으나 중지 상태임" -Evidence "FTPSVC Status=$($svc.Status)"
}

$evid = @("FTPSVC Status=$($svc.Status)")
if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    return New-CheckResult -Code "W-21" -Status "VULN" -Detail "FTP 서비스가 구동 중이며 FTPS(SSL 필수) 설정을 확인할 수 없음(WebAdministration 모듈 없음) - 평문 FTP 로 간주" -Evidence ($evid -join "`n")
}
Import-Module WebAdministration -ErrorAction SilentlyContinue
$apphost = "MACHINE/WEBROOT/APPHOST"
$sslRel = "ftpServer/security/ssl"
function Get-W21Value([string]$Filter, [string]$Name) {
    $a = Get-WebConfigurationProperty -PSPath $apphost -Filter $Filter -Name $Name -ErrorAction Stop
    $v = if ($a.PSObject.Properties.Name -contains "Value") { $a.Value } else { $a }
    $inh = ($a.PSObject.Properties.Name -contains "IsInheritedFromDefaultValue" -and $a.IsInheritedFromDefaultValue)
    return @{ Value = "$v"; Inherited = [bool]$inh }
}
try {
    $sites = @(Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" })
    $def = @{}
    foreach ($n in @("controlChannelPolicy", "dataChannelPolicy")) { $def[$n] = (Get-W21Value "system.applicationHost/sites/siteDefaults/$sslRel" $n).Value }
} catch {
    return New-CheckResult -Code "W-21" -Status "ERROR" -Detail "FTP 사이트/SSL 설정 조회 실패: $($_.Exception.Message)" -Evidence ($evid -join "`n")
}
if ($sites.Count -eq 0) {
    return New-CheckResult -Code "W-21" -Status "VULN" -Detail "FTP 서비스가 구동 중이며 FTPS 로 설정된 FTP 사이트가 없음(등록된 사이트 없음) - 불필요하면 서비스 중지 필요" -Evidence ($evid -join "`n")
}
$plain = @()
foreach ($s in $sites) {
    $eff = @{}
    foreach ($n in @("controlChannelPolicy", "dataChannelPolicy")) {
        try { $r = Get-W21Value "system.applicationHost/sites/site[@name='$($s.Name)']/$sslRel" $n }
        catch { return New-CheckResult -Code "W-21" -Status "ERROR" -Detail "FTP 사이트 '$($s.Name)' SSL 설정 조회 실패: $($_.Exception.Message)" -Evidence ($evid -join "`n") }
        $eff[$n] = if ($r.Inherited) { $def[$n] } else { $r.Value }
    }
    # 열거형은 이름(SslRequire) 또는 숫자(1 = SslRequire, 제어·데이터 채널 공통)로 돌아올 수 있다
    $req = { param($v) $v -eq "SslRequire" -or $v -eq "1" }
    $evid += "[$($s.Name)] controlChannelPolicy=$($eff.controlChannelPolicy) dataChannelPolicy=$($eff.dataChannelPolicy)"
    if (-not ((& $req $eff.controlChannelPolicy) -and (& $req $eff.dataChannelPolicy))) { $plain += $s.Name }
}
if ($plain.Count -gt 0) {
    return New-CheckResult -Code "W-21" -Status "VULN" -Detail ("암호화되지 않은 FTP 가 허용된 사이트(제어·데이터 채널 SSL 필수 아님): " + ($plain -join ", ")) -Evidence ($evid -join "`n")
}
return New-CheckResult -Code "W-21" -Status "GOOD" -Detail "FTP 서비스가 구동 중이나 모든 FTP 사이트가 FTPS(제어·데이터 채널 SSL 필수)로 설정됨" -Evidence ($evid -join "`n")
