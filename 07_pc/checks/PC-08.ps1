# PC-08 (중) 대상 시스템이 Windows 서버를 제외한 다른 OS로 멀티 부팅이 가능하지 않도록 설정
# 판정: bcdedit /enum(활성 항목 = 부팅 관리자 + 부팅 메뉴 displayorder 항목)의 부트 로더 수.
# 항목 수는 각 항목 머리글 아래의 구분선(-----)으로 센다 - 머리글("Windows Boot Loader")은 OS 언어에
# 따라 번역되므로(한글판 "Windows 부팅 로더") 예전처럼 영문 문자열을 세면 한글 Windows 에서 항상 0개 →
# 항상 GOOD 이었다. 구분선 수에서 부팅 관리자 1개를 뺀 값이 부팅 메뉴의 OS 수다.
# /enum osloader 는 복구 환경(WinRE) 로더까지 포함해 단일 OS 에서도 2개가 나오므로 쓰지 않는다.

# W-R16: 시간 제한(60초), 실행 파일은 PATH 가 아닌 System32 경로로 지정
try {
    $res = Invoke-NativeCommand -FilePath (Join-Path $env:SystemRoot "System32\bcdedit.exe") -ArgumentList @('/enum') -TimeoutSec 60
} catch {
    return New-CheckResult -Code "PC-08" -Status "ERROR" -Detail "bcdedit 실행 실패: $($_.Exception.Message)"
}
if ($res.TimedOut) {
    return New-CheckResult -Code "PC-08" -Status "ERROR" -Detail "bcdedit 실행 시간 초과(60초)"
}
$out = (($res.Output -join "`n") + "`n" + $res.ErrorText)
$rc = $res.ExitCode
if ($rc -ne 0) {
    # 관리자 권한이 없으면 "액세스가 거부되었습니다" 와 함께 실패한다 - 예전에는 이 출력에서 0개를 세어 GOOD 이었다
    return New-CheckResult -Code "PC-08" -Status "ERROR" -Detail "bcdedit 실행 실패(exit=$rc) - 관리자 권한으로 다시 실행 필요" -Evidence $out.Trim()
}

$entries = ([regex]::Matches($out, '(?m)^-{5,}\s*$')).Count
$loaderCount = [Math]::Max(0, $entries - 1)
if ($entries -eq 0) {
    return New-CheckResult -Code "PC-08" -Status "ERROR" -Detail "bcdedit 출력 형식을 해석하지 못함 - 시스템 구성(msconfig) 부팅 탭에서 수동 확인 필요" -Evidence $out.Trim()
}

$evidence = "bcdedit /enum 항목 수: $entries (부팅 관리자 1 + 부팅 메뉴 OS $loaderCount)"
if ($loaderCount -le 1) {
    return New-CheckResult -Code "PC-08" -Status "GOOD" -Detail "부팅 메뉴의 OS 항목이 ${loaderCount}개로 단일 OS만 설치되어 있음" -Evidence $evidence
} else {
    return New-CheckResult -Code "PC-08" -Status "VULN" -Detail "부팅 메뉴의 OS 항목이 ${loaderCount}개로 멀티 부팅이 구성되어 있음" -Evidence $evidence
}
