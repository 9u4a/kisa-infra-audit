# PC-07 (중) 파일 시스템이 NTFS 포맷으로 설정
# 판단 기준(가이드 원문): 양호 = 모든 디스크 볼륨이 NTFS / 취약 = FAT32 볼륨이 존재

try {
    $volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
} catch {
    return New-CheckResult -Code "PC-07" -Status "ERROR" -Detail "논리 디스크 조회 실패: $($_.Exception.Message)"
}

$nonNtfs = $volumes | Where-Object { $_.FileSystem -and $_.FileSystem -notmatch "NTFS" }
$evidence = ($volumes | ForEach-Object { "$($_.DeviceID) $($_.FileSystem)" }) -join "`n"

if ($nonNtfs.Count -eq 0) {
    return New-CheckResult -Code "PC-07" -Status "GOOD" -Detail "모든 고정 디스크 볼륨이 NTFS 파일 시스템을 사용함" -Evidence $evidence
} else {
    return New-CheckResult -Code "PC-07" -Status "VULN" -Detail ("NTFS 가 아닌 볼륨 존재: " + (($nonNtfs | ForEach-Object { "$($_.DeviceID)($($_.FileSystem))" }) -join ", ")) -Evidence $evidence
}
