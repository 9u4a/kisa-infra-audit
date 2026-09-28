# W-61 (중) 파일 및 디렉토리 보호
# 판단 기준(가이드 원문): 양호 = NTFS 파일 시스템 사용 / 취약 = FAT 계열 사용

try {
    $volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
} catch {
    return New-CheckResult -Code "W-61" -Status "ERROR" -Detail "논리 디스크 조회 실패: $($_.Exception.Message)"
}

$nonNtfs = $volumes | Where-Object { $_.FileSystem -and $_.FileSystem -notmatch "NTFS" }
$evidence = ($volumes | ForEach-Object { "$($_.DeviceID) $($_.FileSystem)" }) -join "`n"

if ($nonNtfs.Count -eq 0) {
    return New-CheckResult -Code "W-61" -Status "GOOD" -Detail "모든 고정 디스크 볼륨이 NTFS 파일 시스템을 사용함" -Evidence $evidence
} else {
    return New-CheckResult -Code "W-61" -Status "VULN" -Detail ("NTFS 가 아닌 볼륨 존재: " + (($nonNtfs | ForEach-Object { "$($_.DeviceID)($($_.FileSystem))" }) -join ", ")) -Evidence $evidence
}
