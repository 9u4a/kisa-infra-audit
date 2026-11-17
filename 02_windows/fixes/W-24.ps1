# W-24 (상) FTP 접근 제어 설정 [fix: param]
# 값: allow=FTP 접속을 허용할 IPv4 주소(쉼표 구분, 대역은 주소/서브넷마스크 예: 10.0.0.0/255.255.255.0)
# 변경: IIS FTP 마스터(서버) 속성 ipSecurity 에 허용 IP 추가 + 목록에 없는 클라이언트 거부(allowUnlisted=false), 사이트가 다시 연 경우
#       그 사이트 location 도 거부로 - 추가한 IP·바꾼 속성은 백업해 원복 시 되돌림
# 영향: 허용 목록에 없는 IP 의 FTP 접속이 즉시 거부됨(업무용 FTP 클라이언트 IP 가 빠지면 전송이 끊김)
# 가이드 조치 방법: 특정 IP 주소에서만 FTP 서버에 접속하도록 접근 제어(※ 마스터 속성과 모든 사이트에 적용). 허용 IP 를 스크립트가
# 정할 수 없어 manual 이었다 - 1.7.0 값 지정 조치로 운영자가 정책 값 W-24.allow 로 준다.
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): IPv4 주소(·서브넷마스크) 형식, 0.0.0.0(전체 허용) 아님, 중복 없음.

$vals = @(Get-FixParam -Key "allow")
if ($vals.Count -eq 0) {
    $Global:FixStatus = "MANUAL"; $Global:FixDetail = "정책 값 W-24.allow 가 없어 바꾸지 않음"; $Global:FixEvidence = ""
    return
}
$errs = @(); $seen = @{}; $entries = @()
foreach ($v in $vals) {
    if ($seen.ContainsKey($v)) { $errs += "${v}: 값에 두 번 나옴"; continue }
    $seen[$v] = $true
    $ipText, $maskText = $v.Split("/", 2)
    $ip = $null; $mask = $null
    if (-not [System.Net.IPAddress]::TryParse($ipText, [ref]$ip) -or $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $ipText -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $errs += "${v}: IPv4 주소 형식이 아님"; continue }
    if ($ipText -eq "0.0.0.0") { $errs += "${v}: 0.0.0.0 은 전체 허용이라 접근 제어가 아님"; continue }
    $e = @{ ipAddress = $ipText; allowed = "true" }
    if ($maskText) {
        if (-not [System.Net.IPAddress]::TryParse($maskText, [ref]$mask) -or $maskText -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $errs += "${v}: 서브넷마스크 형식이 아님(예: 255.255.255.0)"; continue }
        if ($maskText -eq "0.0.0.0") { $errs += "${v}: 마스크 0.0.0.0 은 전체 허용"; continue }
        $e.subnetMask = $maskText
    }
    $entries += $e
}
try { $svc = Get-ServiceChecked -Name "FTPSVC" } catch { $errs += "FTP(FTPSVC) 서비스 조회 실패: $($_.Exception.Message)" }
if (-not $errs -and (-not $svc -or "$($svc.Status)" -ne "Running")) { $errs += "FTP 서비스가 구동 중이 아님(조치 대상 없음)" }
if ($errs.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "값 검증 실패 - 아무것도 바꾸지 않음: $($errs -join ' / ')"; $Global:FixEvidence = ""
    return
}

Import-Module WebAdministration -ErrorAction Stop
$filter = "/system.ftpServer/security/ipSecurity"
$apphost = "MACHINE/WEBROOT/APPHOST"
$done = @(); $failed = @()
try {
    foreach ($e in $entries) { if (Add-FixWebCollectionItem -Filter $filter -PSPath "IIS:\" -Key "ipAddress" -Value $e) { $done += "허용 $($e.ipAddress)$(if ($e.subnetMask) { '/' + $e.subnetMask })" } }
    Backup-FixWebConfigProperty -Filter $filter -Name "allowUnlisted" -PSPath "IIS:\" | Out-Null
    Set-WebConfigurationProperty -Filter $filter -PSPath "IIS:\" -Name "allowUnlisted" -Value $false -ErrorAction Stop
    $done += "마스터 allowUnlisted=false"
    foreach ($s in @(Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" })) {
        $cur = Get-WebConfigurationProperty -Filter $filter -PSPath $apphost -Location $s.Name -Name "allowUnlisted" -ErrorAction Stop
        if ("$(ConvertTo-FixPlainValue $cur)" -ne "False") {
            Backup-FixWebConfigProperty -Filter $filter -Name "allowUnlisted" -PSPath $apphost -Location $s.Name | Out-Null
            Set-WebConfigurationProperty -Filter $filter -PSPath $apphost -Location $s.Name -Name "allowUnlisted" -Value $false -ErrorAction Stop
            $done += "사이트 $($s.Name) allowUnlisted=false"
        }
    }
} catch {
    if ($_.Exception.Message.StartsWith("[백업 실패]")) { throw }
    $failed += $_.Exception.Message
}
$sec = Get-WebConfiguration -Filter $filter -PSPath "IIS:\" -ErrorAction SilentlyContinue
$Global:FixEvidence = "마스터: allowUnlisted=$($sec.allowUnlisted), 허용 IP=$(@($sec.Collection | Where-Object { "$($_.allowed)" -eq 'True' } | ForEach-Object { $_.ipAddress }) -join ',')"
if ($failed.Count -gt 0) {
    $Global:FixStatus = "ERROR"; $Global:FixDetail = "FTP 접근 제어 설정 실패: $($failed -join ' / ')"
} else {
    $Global:FixStatus = "APPLIED"; $Global:FixDetail = "FTP 접근 제어 적용: $($done -join ', ')"
}
