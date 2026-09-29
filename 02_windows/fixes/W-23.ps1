# W-23 (상) 공유 서비스에 대한 익명 접근 제한 설정 [fix: confirm]
# checks/W-23.ps1 과 동일한 분기: FTP 구동 중이면 익명 인증을 끄고, 아니면 SMB Null Session
# 제한 레지스트리를 설정한다.

$ftpSvc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
if ($ftpSvc -and $ftpSvc.Status -eq "Running") {
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        $Global:FixStatus = "ERROR"
        $Global:FixDetail = "WebAdministration 모듈이 없어 FTP 익명 인증 설정을 변경할 수 없음"
        $Global:FixEvidence = ""
        return
    }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Set-FixWebConfigProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $false -PSPath "IIS:\"
    return
}

Set-FixRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictNullSessAccess" -Value 1 -Type DWord
