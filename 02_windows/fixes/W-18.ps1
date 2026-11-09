# W-18 (상) 불필요한 서비스 제거 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 변경: RemoteRegistry/SSDPSRV/upnphost/simptcp/Browser/WerSvc 중 실행 중이거나 시작 유형이 사용 안 함이 아닌 서비스를 중지 + 시작 유형 사용 안 함
# 영향: 실행 중인 RemoteRegistry/SSDPSRV/upnphost/simptcp/Browser/WerSvc 서비스 중지·사용 안 함 — 이 서비스를 쓰던 원격 관리·검색 기능 중단
# checks/W-18.ps1 과 동일한 대상 목록 중 Running 이거나 시작 유형이 Disabled 가 아닌 서비스를
# 중지+비활성화한다(A8: check 가 트리거 시작으로 잠시 Stopped 인 서비스도 취약으로 보므로 같은 기준).

$targets = @("RemoteRegistry", "SSDPSRV", "upnphost", "simptcp", "Browser", "WerSvc")
$applied = @()
$errors = @()

foreach ($name in $targets) {
    # 표시 이름 일치(예: "Browser" → 커널 드라이버 bowser)는 제외 - checks/W-18 과 같은 기준(F-W18)
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name }
    if ($svc -and ("$($svc.Status)" -eq "Running" -or "$($svc.StartType)" -ne "Disabled")) {
        Disable-FixService -Name $name
        if ($Global:FixStatus -eq "APPLIED") { $applied += $name } else { $errors += $name }
    }
}

if ($errors.Count -gt 0) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "일부 서비스 비활성화 실패: $($errors -join ', ')"
} elseif ($applied.Count -gt 0) {
    $Global:FixStatus = "APPLIED"
    $Global:FixDetail = "불필요 서비스 중지/사용 안 함 설정: $($applied -join ', ')"
} else {
    $Global:FixStatus = "NA"
    $Global:FixDetail = "구동 중이거나 사용 안 함이 아닌 대상 서비스가 없음(이미 정상 상태였던 것으로 추정)"
}
