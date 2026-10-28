# W-40 (중) 정책에 따른 시스템 로깅 설정
# 판단 기준(가이드 원문): 양호 = 감사 정책 권고 기준에 따라 감사 설정이 되어 있는 경우
# 가이드 권고 기준(로컬 정책 > 감사 정책):
#   계정 관리=실패, 계정 로그온 이벤트=성공/실패, 권한 사용=성공/실패,
#   디렉터리 서비스 액세스=실패, 로그온 이벤트=성공/실패, 정책 변경=성공/실패
# W-R6: 예전에는 auditpol /get /r 의 "Inclusion Setting" 문자열("Success and Failure")을 비교했는데 이 값은 OS 언어에
# 따라 번역될 수 있다. auditpol /backup 의 CSV 에서 하위 범주 GUID 와 숫자 "Setting Value"(0=없음 1=성공 2=실패
# 3=성공 및 실패, 로캘 무관)로 판정한다. 열 순서(컴퓨터 이름, 정책 대상, 하위 범주, 하위 범주 GUID, 포함 설정,
# 제외 설정, 설정 값)는 한글 Windows 11 에서 실제 출력으로 확인함 - 머리글 문자열 자체가 번역되므로 위치로 읽는다.
# 백업 파일은 무작위 이름의 전용 폴더(New-PrivateTempFile)에 쓰고 바로 지운다(W-R7), 시간 제한 60초(W-R16).

# 권고 기준: Need = 필요한 비트(1=성공, 2=실패). 설정 값이 이 비트를 모두 포함하면 충족.
$checks = @(
    @{ Name = "계정 관리(Other Account Management Events)"; Guid = "{0CCE923A-69AE-11D9-BED3-505054503030}"; Need = 2 },
    @{ Name = "계정 로그온(Credential Validation)"; Guid = "{0CCE923F-69AE-11D9-BED3-505054503030}"; Need = 3 },
    @{ Name = "권한 사용(Sensitive Privilege Use)"; Guid = "{0CCE9228-69AE-11D9-BED3-505054503030}"; Need = 3 },
    @{ Name = "로그온(Logon)"; Guid = "{0CCE9215-69AE-11D9-BED3-505054503030}"; Need = 3 },
    @{ Name = "정책 변경(Audit Policy Change)"; Guid = "{0CCE922F-69AE-11D9-BED3-505054503030}"; Need = 3 }
)
$label = @{ 0 = "감사 안 함"; 1 = "성공"; 2 = "실패"; 3 = "성공 및 실패" }

$tmp = $null; $rows = $null; $failMsg = ""
try {
    $tmp = New-PrivateTempFile -FileName "auditpol.csv"
    $r = Invoke-NativeCommand -FilePath (Join-Path $env:SystemRoot "System32\auditpol.exe") -ArgumentList @('/backup', "/file:$tmp") -TimeoutSec 60
    if ($r.TimedOut) { $failMsg = "시간 초과(60초)" }
    elseif ($r.ExitCode -ne 0) { $failMsg = "종료 코드 $($r.ExitCode) - 관리자 권한 필요" }
    elseif (-not (Test-Path -LiteralPath $tmp)) { $failMsg = "백업 파일이 생성되지 않음" }
    else {
        # 머리글도 OS 표시 언어로 번역된다(한글판 실측: "하위 범주 GUID", "설정 값") - 열 이름이 아니라 위치(4번째 GUID,
        # 7번째 설정 값)로 읽고 첫 줄(머리글)은 버린다. 형식 확인: GUID 모양 + 숫자 값인 행이 있어야 한다.
        $rows = @(Import-Csv -LiteralPath $tmp -Encoding Default -Header 'C1', 'C2', 'C3', 'Guid', 'C5', 'C6', 'Value' | Select-Object -Skip 1)
        if (@($rows | Where-Object { $_.Guid -match '^\{[0-9A-Fa-f-]{36}\}$' -and "$($_.Value)".Trim() -match '^\d+$' }).Count -eq 0) {
            $failMsg = "auditpol /backup 출력 형식을 해석하지 못함(하위 범주 GUID/설정 값 열 없음)"
        }
    }
} catch {
    $failMsg = $_.Exception.Message
} finally {
    if ($tmp) { Remove-Item -LiteralPath (Split-Path -Parent $tmp) -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($failMsg) {
    return New-CheckResult -Code "W-40" -Status "ERROR" -Detail "auditpol 실행 실패로 감사 정책을 확인하지 못함: $failMsg"
}

$evidence = @()
$violations = @()
$unknown = @()
foreach ($c in $checks) {
    $row = $rows | Where-Object { $_.Guid -eq $c.Guid } | Select-Object -First 1
    $v = $null
    if ($row -and "$($row.Value)".Trim() -match '^\d+$') { $v = [int]"$($row.Value)".Trim() }
    if ($null -eq $v) {
        $unknown += $c.Name
        $evidence += "$($c.Name): 확인 불가(백업에 해당 하위 범주 없음)"
        continue
    }
    $evidence += "$($c.Name): $($label[$v]) (Setting Value=$v)"
    if (($v -band $c.Need) -ne $c.Need) { $violations += $c.Name }
}

if ($violations.Count -gt 0) {
    return New-CheckResult -Code "W-40" -Status "VULN" -Detail ("권고 기준 미충족 감사 항목: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
if ($unknown.Count -gt 0) {
    return New-CheckResult -Code "W-40" -Status "ERROR" -Detail ("감사 설정을 확인하지 못한 항목: " + ($unknown -join ", ")) -Evidence ($evidence -join "`n")
}
return New-CheckResult -Code "W-40" -Status "GOOD" -Detail "감사 정책 권고 기준에 따라 주요 감사 항목이 설정되어 있음" -Evidence ($evidence -join "`n")
