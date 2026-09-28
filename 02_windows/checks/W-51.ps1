# W-51 (상) SAM 계정과 공유의 익명 열거 허용 안 함
# 판단 기준(가이드 원문): 양호 = "SAM 계정과 공유의 익명 열거 허용 안 함"이 "사용"(=1)
#                        취약 = "사용 안 함"(=0)
# 두 레지스트리 값 모두 확인: RestrictAnonymous(SAM+공유, 기본값 0/취약),
# RestrictAnonymousSAM(SAM만, 기본값 1/양호, Windows XP SP2+)

$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$anon = Test-RegistryValue -Path $path -Name "RestrictAnonymous"
$anonSam = Test-RegistryValue -Path $path -Name "RestrictAnonymousSAM"

$anonVal = if ($null -eq $anon) { 0 } else { [int]$anon }
$anonSamVal = if ($null -eq $anonSam) { 1 } else { [int]$anonSam }

$evidence = "RestrictAnonymous=$anon(적용값 $anonVal) RestrictAnonymousSAM=$anonSam(적용값 $anonSamVal)"

if ($anonVal -ge 1 -and $anonSamVal -ge 1) {
    return New-CheckResult -Code "W-51" -Status "GOOD" -Detail "SAM 계정과 공유의 익명 열거가 모두 차단되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-51" -Status "VULN" -Detail "SAM 계정 또는 공유의 익명 열거 차단이 설정되어 있지 않음" -Evidence $evidence
}
