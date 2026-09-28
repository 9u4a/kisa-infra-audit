# D-10 (상) 원격에서 DB 서버로의 접속 제한 [MSSQL]
# 판단 기준(가이드 원문): 양호 = 지정된 IP에서만 접근 가능하도록 제한 / 취약 = 제한 없음
# 가이드 원문의 MSSQL 관련 사례는 Windows 방화벽(원격 데스크톱 규칙 예시)을 통한 접근 제한을
# 다룬다. 특정 규칙 이름에 의존하면 배포 환경마다 깨지므로, 이 항목은 "Windows 방화벽 자체가
# 활성화되어 있는지"(전혀 없으면 명백한 취약)까지만 자동 판정하고, IP 허용 목록의 구체적
# 범위는 MANUAL로 안내한다.

try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
} catch {
    return New-CheckResult -Code "D-10" -Status "ERROR" -Detail "Windows 방화벽 프로필 조회 실패: $($_.Exception.Message)"
}
$evidence = ($profiles | ForEach-Object { "$($_.Name): Enabled=$($_.Enabled)" }) -join "`n"
$allDisabled = -not ($profiles | Where-Object { $_.Enabled })
if ($allDisabled) {
    return New-CheckResult -Code "D-10" -Status "VULN" -Detail "모든 Windows 방화벽 프로필이 비활성화되어 있어 원격 접속 제한이 전혀 없음" -Evidence $evidence
} else {
    return New-CheckResult -Code "D-10" -Status "MANUAL" -Detail "Windows 방화벽은 활성화됨 - DB 포트(기본 1433)에 대해 지정 IP만 허용하는 인바운드 규칙이 실제로 구성되어 있는지 수동 확인 필요" -Evidence $evidence
}
