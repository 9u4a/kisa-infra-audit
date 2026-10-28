# PC-04 (상) 공유 폴더 제거
# 판단 기준(가이드 원문): 양호 = 불필요한 공유 폴더가 없거나, 있다면 접근권한/비밀번호가 설정된 경우
#                        취약 = 불필요한 공유 폴더가 있거나 접근권한/비밀번호 없이 사용되는 경우
# 자동화 범위: 기본(관리용) 공유 존재 여부 + AutoShareWks 값, 일반 공유의 Everyone 권한 여부.

# W-R2: Get-SmbShareAccess 실패를 예전에는 "Everyone 없음"으로 넘겼다 - 실패한 공유가 있으면 ERROR.
# Everyone 은 S-1-1-0 의 이 OS 언어 이름으로 비교한다. W-R16: CDXML cmdlet 시간 제한.
$everyoneNames = @('Everyone')
try { $everyoneNames += (New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')).Translate([System.Security.Principal.NTAccount]).Value } catch { }
try {
    $allShares = @(Invoke-CimCmdletWithTimeout -Command Get-SmbShare)
} catch {
    return New-CheckResult -Code "PC-04" -Status "ERROR" -Detail "Get-SmbShare 실행 실패: $($_.Exception.Message)"
}

$defaultShares = $allShares | Where-Object { $_.Name -match '^[A-Za-z]\$$' -or $_.Name -eq 'ADMIN$' }
$generalShares = $allShares | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'print$' }
$autoShareWks = Test-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "AutoShareWks"

$violations = @()
$evidence = @()

if ($defaultShares.Count -gt 0) {
    $violations += "기본(관리용) 공유 존재: " + (($defaultShares | ForEach-Object { $_.Name }) -join ", ")
}
$evidence += "AutoShareWks=$autoShareWks, 기본 공유: " + (($defaultShares | ForEach-Object { $_.Name }) -join ", ")

$unverified = @()
foreach ($s in $generalShares) {
    try {
        $access = @(Invoke-CimCmdletWithTimeout -Command Get-SmbShareAccess -Parameters @{ Name = $s.Name })
    } catch {
        $unverified += $s.Name
        $evidence += "일반 공유 '$($s.Name)': 접근 권한 조회 실패 - $($_.Exception.Message)"
        continue
    }
    $everyone = @($access | Where-Object { $_.AccessControlType -ne 1 -and $everyoneNames -contains "$($_.AccountName)" })
    $evidence += "일반 공유 '$($s.Name)': " + (($access | ForEach-Object { "$($_.AccountName)=$($_.AccessRight)" }) -join "; ")
    if ($everyone.Count -gt 0) { $violations += "일반 공유 '$($s.Name)' 에 Everyone 권한 존재" }
}

if ($violations.Count -eq 0 -and $unverified.Count -gt 0) {
    return New-CheckResult -Code "PC-04" -Status "ERROR" -Detail ("접근 권한을 조회하지 못한 공유가 있어 판정할 수 없음: " + ($unverified -join ", ")) -Evidence ($evidence -join "`n")
} elseif ($violations.Count -eq 0) {
    return New-CheckResult -Code "PC-04" -Status "GOOD" -Detail "불필요한(기본) 공유가 없고 일반 공유에 Everyone 권한도 없음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "PC-04" -Status "VULN" -Detail ($violations -join "; ") -Evidence ($evidence -join "`n")
}
