# W-23 (상) 공유 서비스에 대한 익명 접근 제한 설정
# 판단 기준(가이드 원문): 양호 = 공유 서비스 미사용 또는 익명 인증 사용 안 함
#                        취약 = 공유 서비스 사용 중 익명 인증 사용함
# 자동화 범위: FTP(익명 인증) 우선 확인, FTP 미사용 시 SMB Null Session 제한 레지스트리로 대체 판정.
# W-R5: FTP 익명 인증은 사이트 단위(sites/site[@name]/ftpServer/security/authentication/anonymousAuthentication)
# 또는 siteDefaults 에 기록되는데, 예전에는 존재하지 않는 경로(IIS:\ 의 system.ftpServer/...)에서 읽어 사이트별
# 설정을 놓쳤다. FTP 사이트마다 유효 값을 읽고, 사이트에 명시 값이 없으면 siteDefaults 값을 쓴다.

# 서비스 조회 실패(권한 부족 등)를 "FTP 미사용"으로 읽지 않는다(S6)
try { $ftpSvc = Get-ServiceChecked -Name "FTPSVC" }
catch { return New-CheckResult -Code "W-23" -Status "ERROR" -Detail "FTP(FTPSVC) 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
if ($ftpSvc -and $ftpSvc.Status -eq "Running") {
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        return New-CheckResult -Code "W-23" -Status "MANUAL" -Detail "FTP 구동 중이나 WebAdministration 모듈이 없어 익명 인증 설정을 자동 조회할 수 없음"
    }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $apphost = "MACHINE/WEBROOT/APPHOST"
    $anonRel = "ftpServer/security/authentication/anonymousAuthentication"
    try {
        $ftpSites = @(Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" })
        $defAttr = Get-WebConfigurationProperty -PSPath $apphost -Filter "system.applicationHost/sites/siteDefaults/$anonRel" -Name enabled -ErrorAction Stop
        $defVal = if ($defAttr.PSObject.Properties.Name -contains "Value") { $defAttr.Value } else { $defAttr }
    } catch {
        return New-CheckResult -Code "W-23" -Status "ERROR" -Detail "FTP 익명 인증 설정 조회 실패: $($_.Exception.Message)"
    }
    if ($ftpSites.Count -eq 0) {
        return New-CheckResult -Code "W-23" -Status "NA" -Detail "FTP 서비스는 구동 중이나 등록된 FTP 사이트가 없음" -Evidence "siteDefaults anonymousAuthentication.enabled=$defVal"
    }
    $vuln = @(); $evid = @("siteDefaults anonymousAuthentication.enabled=$defVal")
    foreach ($s in $ftpSites) {
        try {
            $attr = Get-WebConfigurationProperty -PSPath $apphost -Filter "system.applicationHost/sites/site[@name='$($s.Name)']/$anonRel" -Name enabled -ErrorAction Stop
        } catch {
            return New-CheckResult -Code "W-23" -Status "ERROR" -Detail "FTP 사이트 '$($s.Name)' 익명 인증 설정 조회 실패: $($_.Exception.Message)" -Evidence ($evid -join "`n")
        }
        $val = if ($attr.PSObject.Properties.Name -contains "Value") { $attr.Value } else { $attr }
        # 사이트에 명시 값이 없으면(스키마 기본값 상속) IIS 는 siteDefaults 값을 적용한다
        $inherited = ($attr.PSObject.Properties.Name -contains "IsInheritedFromDefaultValue" -and $attr.IsInheritedFromDefaultValue)
        $eff = if ($inherited) { $defVal } else { $val }
        $evid += "[$($s.Name)] anonymousAuthentication.enabled=$val$(if ($inherited) { " (명시 없음 → siteDefaults=$defVal)" })"
        if ("$eff" -eq "True") { $vuln += $s.Name }
    }
    if ($vuln.Count -gt 0) {
        return New-CheckResult -Code "W-23" -Status "VULN" -Detail ("FTP 익명 인증이 사용으로 설정된 사이트: " + ($vuln -join ", ")) -Evidence ($evid -join "`n")
    }
    return New-CheckResult -Code "W-23" -Status "GOOD" -Detail "모든 FTP 사이트에서 익명 인증이 사용 안 함으로 설정되어 있음" -Evidence ($evid -join "`n")
}

# FTP 미사용 시 SMB Null Session(익명 공유 접근) 제한 레지스트리로 대체 판정.
# 값이 없을 때의 기본값은 1(제한) - Microsoft 문서 "Network access: Restrict anonymous access to Named Pipes and
# Shares"(기본값 Enabled). 권한 거부 등 조회 실패는 run.ps1 이 RegistryQueryFailed 로 ERROR 처리한다.
# 이 정책의 실제 레지스트리 위치는 LanmanServer\Parameters 다(Microsoft 보안 정책 참조). 예전에는 Lsa 아래만 읽어
# 정책을 꺼도 항상 "값 없음 = 기본값" GOOD 이었다 - 두 위치 중 하나라도 0 이면 취약으로 본다.
$path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
$val = Test-RegistryValue -Path $path -Name "RestrictNullSessAccess"
$legacy = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictNullSessAccess"
if ($null -ne $legacy -and "$legacy" -eq "0") { $val = $legacy; $path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" }
if ($val -eq 1 -or $null -eq $val) {
    return New-CheckResult -Code "W-23" -Status "GOOD" -Detail "FTP 미사용, SMB Null Session(익명) 접근이 제한되어 있음(또는 기본값)" -Evidence "$path!RestrictNullSessAccess=$val"
} else {
    return New-CheckResult -Code "W-23" -Status "VULN" -Detail "FTP 미사용이나 SMB Null Session(익명) 접근 제한이 해제되어 있음" -Evidence "$path!RestrictNullSessAccess=$val"
}
