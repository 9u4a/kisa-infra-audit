# W-23 (상) 공유 서비스에 대한 익명 접근 제한 설정
# 판단 기준(가이드 원문): 양호 = 공유 서비스 미사용 또는 익명 인증 사용 안 함
#                        취약 = 공유 서비스 사용 중 익명 인증 사용함
# 자동화 범위: FTP(익명 인증) 우선 확인, FTP 미사용 시 SMB Null Session 제한 레지스트리로 대체 판정.

$ftpSvc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
if ($ftpSvc -and $ftpSvc.Status -eq "Running") {
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        return New-CheckResult -Code "W-23" -Status "MANUAL" -Detail "FTP 구동 중이나 WebAdministration 모듈이 없어 익명 인증 설정을 자동 조회할 수 없음"
    }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    try {
        $anon = Get-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -Name enabled -PSPath "IIS:\" -ErrorAction Stop
        if ($anon.Value -eq $true) {
            return New-CheckResult -Code "W-23" -Status "VULN" -Detail "FTP 익명 인증이 사용으로 설정되어 있음" -Evidence "anonymousAuthentication.enabled=$($anon.Value)"
        } else {
            return New-CheckResult -Code "W-23" -Status "GOOD" -Detail "FTP 익명 인증이 사용 안 함으로 설정되어 있음" -Evidence "anonymousAuthentication.enabled=$($anon.Value)"
        }
    } catch {
        return New-CheckResult -Code "W-23" -Status "MANUAL" -Detail "FTP 익명 인증 설정 조회 실패: $($_.Exception.Message)"
    }
}

# FTP 미사용 시 SMB Null Session(익명 공유 접근) 제한 레지스트리로 대체 판정
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$val = Test-RegistryValue -Path $path -Name "RestrictNullSessAccess"
if ($val -eq 1 -or $null -eq $val) {
    return New-CheckResult -Code "W-23" -Status "GOOD" -Detail "FTP 미사용, SMB Null Session(익명) 접근이 제한되어 있음(또는 기본값)" -Evidence "$path!RestrictNullSessAccess=$val"
} else {
    return New-CheckResult -Code "W-23" -Status "VULN" -Detail "FTP 미사용이나 SMB Null Session(익명) 접근 제한이 해제되어 있음" -Evidence "$path!RestrictNullSessAccess=$val"
}
