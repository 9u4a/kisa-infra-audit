# W-24 (상) FTP 접근 제어 설정
# 판단 기준(가이드 원문): 양호 = 특정 IP에서만 FTP 접속하도록 접근 제어 적용(또는 FTP 미사용)
#                        취약 = 접근 제어 미적용

$svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    return New-CheckResult -Code "W-24" -Status "GOOD" -Detail "FTP 서비스를 사용하지 않음"
}

if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
    return New-CheckResult -Code "W-24" -Status "MANUAL" -Detail "FTP 구동 중이나 WebAdministration 모듈이 없어 IP 접근 제어 설정을 자동 조회할 수 없음"
}

Import-Module WebAdministration -ErrorAction SilentlyContinue
try {
    $ipsec = Get-WebConfiguration -Filter "/system.ftpServer/security/ipSecurity" -PSPath "IIS:\" -ErrorAction Stop
    $denyByDefault = $ipsec.denyByDefault
    $ruleCount = @($ipsec.Collection).Count
    $evidence = "denyByDefault=$denyByDefault, 규칙 수=$ruleCount"
    if ($denyByDefault -eq $true -and $ruleCount -gt 0) {
        return New-CheckResult -Code "W-24" -Status "GOOD" -Detail "기본 거부 후 특정 IP만 허용하도록 설정되어 있음" -Evidence $evidence
    } else {
        return New-CheckResult -Code "W-24" -Status "VULN" -Detail "특정 IP로 제한하는 접근 제어가 적용되어 있지 않음" -Evidence $evidence
    }
} catch {
    return New-CheckResult -Code "W-24" -Status "MANUAL" -Detail "FTP IP 접근 제어 설정 조회 실패: $($_.Exception.Message)"
}
