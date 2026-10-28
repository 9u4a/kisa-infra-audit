# W-16 (상) 공유 권한 및 사용자 그룹 설정
# 판단 기준(가이드 원문): 양호 = 일반 공유 디렉터리가 없거나 Everyone 권한이 없는 경우
#                        취약 = 일반 공유 디렉터리 접근 권한에 Everyone 이 있는 경우
# 기본 관리 공유(C$, ADMIN$, IPC$ 등 $ 로 끝나는 공유)는 W-17 에서 별도로 다루므로 제외한다.
# W-R2: Get-SmbShareAccess 실패(권한 부족 등)를 예전에는 "Everyone 없음"=GOOD 으로 처리했다. 실패한 공유가
# 있으면 ERROR. Everyone 은 이름 대신 SID(S-1-1-0)로 비교한다(비영문 OS). W-R16: CDXML cmdlet 시간 제한.

# 공유 ACL 의 AccountName 은 이름 문자열이라, S-1-1-0 을 이 OS 언어의 이름으로 한 번 바꿔 비교한다(계정마다 SID 변환하면 도메인 계정은 DC 질의).
$everyoneNames = @('Everyone')
try { $everyoneNames += (New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')).Translate([System.Security.Principal.NTAccount]).Value } catch { }
try {
    $shares = @(Invoke-CimCmdletWithTimeout -Command Get-SmbShare | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'print$' })
} catch {
    return New-CheckResult -Code "W-16" -Status "ERROR" -Detail "Get-SmbShare 실행 실패: $($_.Exception.Message)"
}
# DC 의 SYSVOL/NETLOGON 은 Everyone 읽기가 기본 설계(그룹 정책·로그온 스크립트 배포)다 - 취약으로 잡으면
# 이를 근거로 한 조치(fixes/W-16)가 도메인 전체 GPO 처리를 깨뜨리므로 판정에서 제외한다.
# W-R14: DC 여부를 판별하지 못했으면(IsDcUnknown) 두 공유를 단정하지 않고 수동 확인으로 남긴다.
$dcSpecial = @('SYSVOL', 'NETLOGON')
$isDc = Test-IsDomainController
$dcUnknown = [bool]$Global:IsDcUnknown

if ($shares.Count -eq 0) {
    return New-CheckResult -Code "W-16" -Status "GOOD" -Detail "일반(비관리용) 공유 디렉터리가 존재하지 않음"
}

$violations = @()
$unverified = @()
$manual = @()
$evidence = @()
foreach ($s in $shares) {
    if ($isDc -and -not $dcUnknown -and $dcSpecial -contains $s.Name) { continue }
    try {
        $access = @(Invoke-CimCmdletWithTimeout -Command Get-SmbShareAccess -Parameters @{ Name = $s.Name })
    } catch {
        $unverified += $s.Name
        $evidence += "공유 '$($s.Name)' ($($s.Path)): 접근 권한 조회 실패 - $($_.Exception.Message)"
        continue
    }
    $everyone = @($access | Where-Object { $_.AccessControlType -ne 1 -and $everyoneNames -contains "$($_.AccountName)" })
    $evidence += "공유 '$($s.Name)' ($($s.Path)): " + (($access | ForEach-Object { "$($_.AccountName)=$($_.AccessRight)/$($_.AccessControlType)" }) -join "; ")
    if ($everyone.Count -gt 0) {
        if ($dcUnknown -and $dcSpecial -contains $s.Name) { $manual += $s.Name } else { $violations += $s.Name }
    }
}

if ($violations.Count -gt 0) {
    return New-CheckResult -Code "W-16" -Status "VULN" -Detail ("Everyone 권한이 부여된 공유: " + ($violations -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($unverified.Count -gt 0) {
    return New-CheckResult -Code "W-16" -Status "ERROR" -Detail ("접근 권한을 조회하지 못한 공유가 있어 판정할 수 없음: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($manual.Count -gt 0) {
    return New-CheckResult -Code "W-16" -Status "MANUAL" -Detail ("도메인 컨트롤러 여부를 확인하지 못해 SYSVOL/NETLOGON 의 Everyone 권한이 기본 설계인지 판단할 수 없음: " + ($manual -join ", ")) -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "W-16" -Status "GOOD" -Detail "일반 공유 디렉터리에 Everyone 권한이 없음" -Evidence ($evidence -join "`n")
}
