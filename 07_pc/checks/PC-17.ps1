# PC-17 (상) 이동식 미디어에 대한 보안대책 수립 (자동 실행 방지)
# 판단 기준(가이드 원문): 양호 = 미디어 자동 실행 방지 + 내부 관리 절차 수립·이행
#                        취약 = 자동 실행되거나 관리 절차 미수립
# NoDriveTypeAutoRun 비트마스크: 0xFF(255)=모든 드라이브 자동 실행 사용 안 함

$val = Test-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun"

if ($null -ne $val -and ([int]$val -band 0xFF) -eq 0xFF) {
    return New-CheckResult -Code "PC-17" -Status "GOOD" -Detail "모든 드라이브 유형에 대해 자동 실행이 사용 안 함으로 명시적으로 설정됨" -Evidence "NoDriveTypeAutoRun=$val (0x$([Convert]::ToString([int]$val,16)))"
} else {
    return New-CheckResult -Code "PC-17" -Status "MANUAL" -Detail "명시적인 전체 드라이브 자동 실행 차단 정책(NoDriveTypeAutoRun=0xFF)이 설정되어 있지 않음. 최신 Windows는 보안 업데이트로 이동식 미디어 자동 실행을 기본 차단하나, 명시적 정책 설정 및 내부 관리 절차 수립 여부는 수동 확인 필요" -Evidence "NoDriveTypeAutoRun=$val"
}
