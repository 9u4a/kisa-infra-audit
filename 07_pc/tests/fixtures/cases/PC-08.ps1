# PC-08 케이스. 가이드: 양호 = 하나의 OS 만 설치 / 취약 = 2개 이상(부팅 메뉴의 OS 항목). bcdedit /copy 로 부팅 항목을 하나 더 만든다. 조치는 manual.
@{
    Resources = @(@{
            Save    = { $null }
            Restore = {
                param($x)
                $out = & bcdedit.exe /enum all
                $ids = @(); $cur = $null
                foreach ($l in $out) { if ($l -match '^identifier\s+(\{[0-9a-fA-F-]+\})') { $cur = $Matches[1] }; if ($l -match '^description\s+kisa case loader') { $ids += $cur } }
                foreach ($id in $ids) { & bcdedit.exe /delete $id /cleanup | Out-Null }
            }
        })
    States    = [ordered]@{
        'two-loaders'   = @{
            Set   = {
                $o = (& bcdedit.exe /copy '{current}' /d 'kisa case loader') -join ' '
                if ($o -notmatch '(\{[0-9a-fA-F-]{36}\})') { throw "bcdedit /copy 실패: $o" }
                & bcdedit.exe /displayorder $Matches[1] /addlast | Out-Null
            }
            Check = { $n = ([regex]::Matches(((& bcdedit.exe /enum) -join "`n"), '(?m)^-{5,}\s*$')).Count; if ($n -ge 3) { $true } else { "항목 수 $n" } }
        }
        'single-loader' = @{
            Check = { $n = ([regex]::Matches(((& bcdedit.exe /enum) -join "`n"), '(?m)^-{5,}\s*$')).Count; if ($n -eq 2) { $true } else { "항목 수 $n" } }
        }
    }
}