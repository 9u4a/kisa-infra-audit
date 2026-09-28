# W-44 (상) 원격으로 액세스할 수 있는 레지스트리 경로
# 판단 기준(가이드 원문): 양호 = Remote Registry Service 가 중지된 경우 / 취약 = 사용 중인 경우

$svc = Get-Service -Name "RemoteRegistry" -ErrorAction SilentlyContinue
if (-not $svc) {
    return New-CheckResult -Code "W-44" -Status "GOOD" -Detail "Remote Registry 서비스가 존재하지 않음"
}

if ($svc.Status -ne "Running") {
    return New-CheckResult -Code "W-44" -Status "GOOD" -Detail "Remote Registry 서비스가 중지되어 있음" -Evidence "Status=$($svc.Status) StartType=$($svc.StartType)"
} else {
    return New-CheckResult -Code "W-44" -Status "VULN" -Detail "Remote Registry 서비스가 구동 중임" -Evidence "Status=$($svc.Status) StartType=$($svc.StartType)"
}
