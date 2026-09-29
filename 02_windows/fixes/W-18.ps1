# W-18 (상) 불필요한 서비스 제거 [fix: auto]
# checks/W-18.ps1 과 동일한 대상 목록 중 실제로 Running 인 서비스만 중지+비활성화한다.

$targets = @("RemoteRegistry", "SSDPSRV", "upnphost", "simptcp", "Browser", "WerSvc")
$applied = @()
$errors = @()

foreach ($name in $targets) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
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
