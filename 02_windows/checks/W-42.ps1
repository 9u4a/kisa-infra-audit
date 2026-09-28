# W-42 (하) 이벤트 로그 관리 설정
# 판단 기준(가이드 원문): 양호 = 최대 로그 크기 10,240KB 이상 (+구버전은 90일 이후 덮어씀)
#                        취약 = 10,240KB 미만
# 참고: Windows 2008 이상은 UI 상 "N일 이후 덮어쓰기" 지정이 사라졌으므로(가이드 원문 각주),
#      본 자동화는 최대 로그 크기 기준만 판정한다.

$logs = @("Application", "Security", "System")
$violations = @()
$evidence = @()

foreach ($logName in $logs) {
    try {
        $log = Get-WinEvent -ListLog $logName -ErrorAction Stop
        $maxKb = [int]($log.MaximumSizeInBytes / 1KB)
        $evidence += "$logName : MaximumSizeInBytes=$($log.MaximumSizeInBytes) (${maxKb}KB)"
        if ($maxKb -lt 10240) { $violations += "$logName(${maxKb}KB)" }
    } catch {
        $evidence += "$logName : 조회 실패"
    }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "W-42" -Status "GOOD" -Detail "주요 이벤트 로그의 최대 크기가 10,240KB 이상으로 설정됨" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-42" -Status "VULN" -Detail ("최대 크기가 10,240KB 미만인 로그: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
}
