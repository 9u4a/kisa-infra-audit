# W-23 (상) 공유 서비스에 대한 익명 접근 제한 설정 [fix: confirm]
# checks/W-23.ps1 과 같은 분기·같은 위치를 고친다(F-R1 - 예전에는 진단이 보지 않는 Lsa 경로와 존재하지 않는
# IIS:\ 의 system.ftpServer 경로에 써서 재검증 실패 → 원복으로 끝났다).
#  - FTP 구동 중: FTP 사이트마다 진단과 같은 방법으로 익명 인증 값을 읽어, 사이트에 명시 값이 true 면 그 사이트
#    (sites/site[@name]/ftpServer/...)를, 명시 값 없이 siteDefaults 를 상속해 true 면 siteDefaults 를 false 로 바꾼다.
#    백업·원복은 Set-FixWebConfigProperty(바꾼 위치에 이전 값을 다시 씀).
#  - FTP 미사용: SMB Null Session 제한 정책의 실제 위치(LanmanServer\Parameters) RestrictNullSessAccess=1,
#    진단이 함께 보는 예전 위치(Lsa)에 0 이 남아 있으면 그것도 1 로(둘 다 레지스트리 백업·원복).

$ftpSvc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
if ($ftpSvc -and $ftpSvc.Status -eq "Running") {
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "WebAdministration 모듈이 없어 FTP 익명 인증 설정을 변경할 수 없음"
        $Global:FixEvidence = ""
        return
    }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $apphost = "MACHINE/WEBROOT/APPHOST"
    $anonRel = "ftpServer/security/authentication/anonymousAuthentication"
    $defFilter = "system.applicationHost/sites/siteDefaults/$anonRel"
    try {
        $ftpSites = @(Get-Website -ErrorAction Stop | Where-Object { $_.Bindings.Collection.protocol -contains "ftp" })
        $defAttr = Get-WebConfigurationProperty -PSPath $apphost -Filter $defFilter -Name enabled -ErrorAction Stop
        $defVal = if ($defAttr.PSObject.Properties.Name -contains "Value") { $defAttr.Value } else { $defAttr }
    } catch {
        $Global:FixStatus = "ERROR"; $Global:FixDetail = "FTP 익명 인증 설정 조회 실패: $($_.Exception.Message)"; $Global:FixEvidence = ""
        return
    }
    $applied = @(); $failed = @(); $defaultsFixed = $false
    foreach ($s in $ftpSites) {
        $siteFilter = "system.applicationHost/sites/site[@name='$($s.Name)']/$anonRel"
        try { $attr = Get-WebConfigurationProperty -PSPath $apphost -Filter $siteFilter -Name enabled -ErrorAction Stop }
        catch { $failed += "$($s.Name): 조회 실패 $($_.Exception.Message)"; continue }
        $val = if ($attr.PSObject.Properties.Name -contains "Value") { $attr.Value } else { $attr }
        $inherited = ($attr.PSObject.Properties.Name -contains "IsInheritedFromDefaultValue" -and $attr.IsInheritedFromDefaultValue)
        if ($inherited) {
            # 사이트 명시 값 없음 → siteDefaults 값이 적용된다(진단과 같은 해석). siteDefaults 를 한 번만 고친다.
            if ("$defVal" -ne "True") { continue }
            if ($defaultsFixed) { $applied += "$($s.Name)(siteDefaults 상속)"; continue }
            Set-FixWebConfigProperty -Filter $defFilter -Name "enabled" -Value $false -PSPath $apphost
            if ($Global:FixStatus -eq "APPLIED") { $defaultsFixed = $true; $applied += "siteDefaults → $($s.Name)(상속)" }
            else { $failed += "siteDefaults: $($Global:FixDetail)" }
        } elseif ("$val" -eq "True") {
            Set-FixWebConfigProperty -Filter $siteFilter -Name "enabled" -Value $false -PSPath $apphost
            if ($Global:FixStatus -eq "APPLIED") { $applied += $s.Name } else { $failed += "$($s.Name): $($Global:FixDetail)" }
        }
    }
    $Global:FixEvidence = ""
    if ($failed.Count -gt 0) {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "FTP 익명 인증 조치 실패: $($failed -join ' / ')$(if ($applied) { " (적용됨: $($applied -join ', '))" })"
    } elseif ($applied.Count -gt 0) {
        $Global:FixStatus = "APPLIED"
        $Global:FixDetail = "FTP 익명 인증을 사용 안 함으로 설정함: $($applied -join ', ')"
    } else {
        $Global:FixStatus = "NA"
        $Global:FixDetail = "익명 인증이 사용으로 설정된 FTP 사이트가 없음(이미 정상)"
    }
    return
}

$lanPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$legacy = Test-RegistryValue -Path $lsaPath -Name "RestrictNullSessAccess"
Set-FixRegistryValue -Path $lanPath -Name "RestrictNullSessAccess" -Value 1 -Type DWord
if ($Global:FixStatus -ne "APPLIED") { return }
if ($null -ne $legacy -and "$legacy" -eq "0") {
    $first = $Global:FixDetail
    Set-FixRegistryValue -Path $lsaPath -Name "RestrictNullSessAccess" -Value 1 -Type DWord
    $Global:FixDetail = "$first / $($Global:FixDetail)"
}
