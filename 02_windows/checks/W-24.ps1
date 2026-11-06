# W-24 (상) FTP 접근 제어 설정
# 판단 기준(가이드 원문): 양호 = 특정 IP주소에서만 FTP 서버에 접속하도록 접근 제어 설정을 적용한 경우(또는 FTP 미사용)
#                        취약 = 적용하지 않은 경우 ※ 조치 시 마스터 속성과 모든 사이트에 적용함
# 판정: 목록에 없는 클라이언트 거부(allowUnlisted=False) + 허용 IP 1개 이상.
# A9: 예전에는 서버 수준(IIS:\, 마스터 속성)만 읽어, 사이트 단위 <location> 에서 allowUnlisted=true 로 되돌린 사이트를 놓쳤다
# (마스터만 막고 사이트는 열린 상태가 GOOD). 가이드 비고대로 마스터 속성과 FTP 사이트마다의 유효 설정을 모두 확인한다.
# 조회 실패는 MANUAL 이 아니라 ERROR(S6, 루트 CLAUDE.md "조회 실패 → ERROR").

try { $svc = Get-ServiceChecked -Name "FTPSVC" }
catch { return New-CheckResult -Code "W-24" -Status "ERROR" -Detail "FTP(FTPSVC) 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
if (-not $svc -or "$($svc.Status)" -ne "Running") {
    return New-CheckResult -Code "W-24" -Status "GOOD" -Detail "FTP 서비스를 사용하지 않음"
}

if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    return New-CheckResult -Code "W-24" -Status "MANUAL" -Detail "FTP 구동 중이나 WebAdministration 모듈이 없어 IP 접근 제어 설정을 자동 조회할 수 없음"
}

Import-Module WebAdministration -ErrorAction SilentlyContinue
$filter = "/system.ftpServer/security/ipSecurity"
$apphost = "MACHINE/WEBROOT/APPHOST"

function Get-W24IpSecurityState {
    <# ipSecurity 섹션 → 판정용 요약. -Location 이 있으면 그 사이트에 적용되는 유효(상속 합친) 설정 #>
    param([string]$Location = "")
    if ($Location) { $sec = Get-WebConfiguration -Filter $filter -PSPath $apphost -Location $Location -ErrorAction Stop }
    else { $sec = Get-WebConfiguration -Filter $filter -PSPath "IIS:\" -ErrorAction Stop }
    if ($null -eq $sec) { throw "ipSecurity 섹션을 읽지 못함" }
    # F-W24(1.4.0): FTP ipSecurity 의 "목록에 없는 클라이언트 허용" 속성은 allowUnlisted 다(기본 true).
    $allowUnlisted = $sec.allowUnlisted
    $rules = @($sec.Collection)
    $allowRules = @($rules | Where-Object { "$($_.allowed)" -eq "True" }).Count
    return [PSCustomObject]@{
        Restricted = ("$allowUnlisted" -eq "False" -and $allowRules -gt 0)
        Text       = "allowUnlisted=$allowUnlisted, 규칙 수=$($rules.Count)(허용 $allowRules)"
    }
}

$evidence = @()
$open = @()
try {
    $master = Get-W24IpSecurityState
    $evidence += "[마스터(서버) 속성] $($master.Text)"
    if (-not $master.Restricted) { $open += "마스터(서버) 속성" }
    $ftpSites = @(Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" })
} catch {
    return New-CheckResult -Code "W-24" -Status "ERROR" -Detail "FTP IP 접근 제어 설정 조회 실패: $($_.Exception.Message)" -Evidence ($evidence -join "`n")
}
foreach ($s in $ftpSites) {
    try { $st = Get-W24IpSecurityState -Location $s.Name }
    catch { return New-CheckResult -Code "W-24" -Status "ERROR" -Detail "FTP 사이트 '$($s.Name)' IP 접근 제어 설정 조회 실패: $($_.Exception.Message)" -Evidence ($evidence -join "`n") }
    $evidence += "[$($s.Name)] $($st.Text)"
    if (-not $st.Restricted) { $open += "사이트 '$($s.Name)'" }
}
if ($ftpSites.Count -eq 0) { $evidence += "등록된 FTP 사이트 없음(마스터 속성만 판정)" }

if ($open.Count -gt 0) {
    return New-CheckResult -Code "W-24" -Status "VULN" -Detail ("특정 IP로 제한하는 접근 제어(목록에 없는 클라이언트 거부 + 허용 IP)가 적용되지 않음: " + ($open -join ", ")) -Evidence ($evidence -join "`n")
}
return New-CheckResult -Code "W-24" -Status "GOOD" -Detail "마스터 속성과 모든 FTP 사이트에서 기본 거부 후 특정 IP만 허용하도록 설정되어 있음" -Evidence ($evidence -join "`n")
