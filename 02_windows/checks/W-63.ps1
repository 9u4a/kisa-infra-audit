# W-63 (중) 도메인 컨트롤러-사용자의 시간 동기화
# 판단 기준(가이드 원문): 양호 = Kerberos 컴퓨터 시계 동기화 최대 허용 오차가 5분 이하
#                        취약 = 5분 초과
# 도메인 컨트롤러 전용 정책(Kerberos 정책)이므로, 도메인 컨트롤러가 아닌 경우 NA 로 처리한다.

$productType = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).ProductType
# ProductType: 1=워크스테이션/멤버서버, 2=도메인 컨트롤러, 3=서버
if ($productType -ne 2) {
    return New-CheckResult -Code "W-63" -Status "NA" -Detail "이 시스템은 도메인 컨트롤러가 아니므로 Kerberos 정책이 적용되지 않음" -Evidence "ProductType=$productType"
}

$val = Get-SecPolicyValue -Section "Kerberos Policy" -Name "MaxClockSkew"
if ($null -eq $val) {
    return New-CheckResult -Code "W-63" -Status "MANUAL" -Detail "secedit 에서 Kerberos MaxClockSkew 값을 조회하지 못함 — 그룹 정책(GPMC)에서 수동 확인 필요"
}

if ([int]$val -le 5) {
    return New-CheckResult -Code "W-63" -Status "GOOD" -Detail "컴퓨터 시계 동기화 최대 허용 오차가 ${val}분(5분 이하)으로 설정됨" -Evidence "MaxClockSkew=$val"
} else {
    return New-CheckResult -Code "W-63" -Status "VULN" -Detail "컴퓨터 시계 동기화 최대 허용 오차가 ${val}분으로 5분을 초과함" -Evidence "MaxClockSkew=$val"
}
