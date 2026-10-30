# W-18 (상) 불필요한 서비스 제거 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# checks/W-18.ps1 과 동일한 대상 목록 중 실제로 Running 인 서비스만 중지+비활성화한다.

$targets = @("RemoteRegistry", "SSDPSRV", "upnphost", "simptcp", "Browser", "WerSvc")
$applied = @()
$errors = @()

foreach ($name in $targets) {
    # 표시 이름 일치(예: "Browser" → 커널 드라이버 bowser)는 제외 - checks/W-18 과 같은 기준(F-W18)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name }
    if ($svc -and $svc.Status -eq "Running") {
        Disable-FixService -Name $name
        if ($Global:FixStatus -eq "APPLIED") { $applied += $name } else { $errors += $name }
    }
}

if ($errors.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "일부 서비스 비활성화 실패: $($errors -join ', ')"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "구동 중이던 불필요 서비스 중지/비활성화: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "구동 중인 대상 서비스가 없음(이미 정상 상태였던 것으로 추정)"
}
