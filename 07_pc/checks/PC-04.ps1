# PC-04 (상) 공유 폴더 제거
# 판단 기준(가이드 원문): 양호 = 불필요한 공유 폴더가 없거나, 있다면 접근권한/비밀번호가 설정된 경우
#                        취약 = 불필요한 공유 폴더가 있거나 접근권한/비밀번호 없이 사용되는 경우
# 자동화 범위: 기본(관리용) 공유 존재 여부 + AutoShareWks 값, 일반 공유의 Everyone 권한 여부.

try {
    $allShares = Get-SmbShare -ErrorAction Stop
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

foreach ($s in $generalShares) {
    $access = Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue
    $everyone = $access | Where-Object { $_.AccountName -match "Everyone" }
    $evidence += "일반 공유 '$($s.Name)': " + (($access | ForEach-Object { "$($_.AccountName)=$($_.AccessRight)" }) -join "; ")
    if ($everyone) { $violations += "일반 공유 '$($s.Name)' 에 Everyone 권한 존재" }
}

if ($violations.Count -eq 0) {
    return New-CheckResult -Code "PC-04" -Status "GOOD" -Detail "불필요한(기본) 공유가 없고 일반 공유에 Everyone 권한도 없음" -Evidence ($evidence -join "`n")
} else {
    return New-CheckResult -Code "PC-04" -Status "VULN" -Detail ($violations -join "; ") -Evidence ($evidence -join "`n")
}
