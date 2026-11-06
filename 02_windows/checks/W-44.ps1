# W-44 (상) 원격으로 액세스할 수 있는 레지스트리 경로
# 판단 기준(가이드 원문): 양호 = Remote Registry Service 가 중지된 경우 / 취약 = 사용 중인 경우
# 가이드 조치: "불필요 시 서비스 중지 및 사용 안 함으로 설정".
# A8: 예전에는 Status≠Running 이면 GOOD 이었다. Remote Registry 는 트리거 시작(원격 레지스트리 요청 시 기동)·유휴 시 자동 중지
# 서비스라 시작 유형이 자동/수동이면 진단 순간에만 Stopped 일 뿐 원격 요청이 오면 다시 켜진다(= 사용 중). 시작 유형이
# 사용 안 함(Disabled)이고 실행 중이 아닐 때만 "중지"로 본다(guide.json deviation). 조회 실패는 ERROR(S6).

try { $svc = Get-ServiceChecked -Name "RemoteRegistry" }
catch { return New-CheckResult -Code "W-44" -Status "ERROR" -Detail "Remote Registry 서비스 상태를 조회하지 못함: $($_.Exception.Message)" }
if (-not $svc) {
    return New-CheckResult -Code "W-44" -Status "GOOD" -Detail "Remote Registry 서비스가 존재하지 않음"
}

$evidence = "Status=$($svc.Status) StartType=$($svc.StartType)"
if ("$($svc.Status)" -eq "Running") {
    return New-CheckResult -Code "W-44" -Status "VULN" -Detail "Remote Registry 서비스가 구동 중임" -Evidence $evidence
}
if ("$($svc.StartType)" -eq "Disabled") {
    return New-CheckResult -Code "W-44" -Status "GOOD" -Detail "Remote Registry 서비스가 중지되어 있고 시작 유형이 사용 안 함임" -Evidence $evidence
}
return New-CheckResult -Code "W-44" -Status "VULN" -Detail "Remote Registry 서비스가 지금은 중지 상태이나 시작 유형이 $($svc.StartType) 라 원격 요청(트리거)·재부팅 시 다시 시작됨 - 사용 안 함으로 설정 필요" -Evidence $evidence
