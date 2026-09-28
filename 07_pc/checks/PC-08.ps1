# PC-08 (중) 대상 시스템이 Windows 서버를 제외한 다른 OS로 멀티 부팅이 가능하지 않도록 설정
# 판단 기준(가이드 원문): 양호 = PC 내에 하나의 OS만 설치 / 취약 = 2개 이상의 OS 설치

try {
    $out = & bcdedit /enum 2>&1 | Out-String
} catch {
    return New-CheckResult -Code "PC-08" -Status "MANUAL" -Detail "bcdedit 실행 실패 — 수동으로 시스템 구성(msconfig)에서 부팅 항목을 확인 필요"
}

$loaderCount = ([regex]::Matches($out, "Windows Boot Loader")).Count

if ($loaderCount -le 1) {
    return New-CheckResult -Code "PC-08" -Status "GOOD" -Detail "부트 로더 항목이 ${loaderCount}개로 단일 OS만 설치되어 있음" -Evidence "Windows Boot Loader 항목 수: $loaderCount"
} else {
    return New-CheckResult -Code "PC-08" -Status "VULN" -Detail "부트 로더 항목이 ${loaderCount}개로 멀티 부팅이 구성되어 있음" -Evidence "Windows Boot Loader 항목 수: $loaderCount"
}
