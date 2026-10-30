# PC-07 케이스. 가이드: 양호 = 모든 디스크 볼륨이 NTFS / 취약 = FAT32 볼륨. 64MB VHD 를 붙여 FAT32 고정 디스크 볼륨을 만든다. 조치는 manual.
@{
    Resources = @(@{ Save = { $null }; Restore = { param($x) Dismount-CaseFatVolume } })
    States    = [ordered]@{
        'fat32-volume' = @{ Set = { Mount-CaseFatVolume }; Check = { $v = Get-CaseNonNtfsFixedVolumes; if ($v.Count -gt 0) { $true } else { "FAT 볼륨 없음" } } }
        'ntfs-only'    = @{ Check = { $v = Get-CaseNonNtfsFixedVolumes; if ($v.Count -eq 0) { $true } else { "NTFS 아닌 볼륨: $($v -join ',')" } } }
    }
}