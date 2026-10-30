# PC-13 케이스. 가이드: 양호 = 백신 설치 + 최신 업데이트 / 취약 = 미설치 또는 업데이트 안 됨(Defender 서명 경과 7일 초과).
# 취약 상태는 MpCmdRun -RemoveDefinitions -All 로 만들고 서명 업데이트로 원복. 조치(서명 업데이트)는 되돌릴 대상이 없다(Irreversible).
@{
    # MpCmdRun 은 실행 계정 TEMP 에 MpCmdRun.log 를 남긴다 - 케이스 전에 없던 것이면 지운다
    Resources = @(@{ Save = { Test-Path -LiteralPath (Join-Path $env:TEMP 'MpCmdRun.log') }; Restore = { param($e) if (-not $e) { Remove-Item -LiteralPath (Join-Path $env:TEMP 'MpCmdRun.log') -Force -ErrorAction SilentlyContinue } } }, @{ Save = { $null }; Restore = { param($x) if ((Get-MpComputerStatus).AntivirusSignatureAge -gt 7) { Update-CaseDefenderSignatures } } })
    States    = [ordered]@{
        'signatures-removed' = @{ Set = { Remove-CaseDefenderSignatures }; Check = { $a = (Get-MpComputerStatus).AntivirusSignatureAge; if ($a -gt 7) { $true } else { "AntivirusSignatureAge=$a" } } }
        'signatures-current' = @{ Set = { if ((Get-MpComputerStatus).AntivirusSignatureAge -gt 7) { Update-CaseDefenderSignatures } }; Check = { $a = (Get-MpComputerStatus).AntivirusSignatureAge; if ($a -le 7) { $true } else { "AntivirusSignatureAge=$a" } } }
    }
    Fix       = @{ From = 'signatures-removed'; AfterRollback = 'GOOD'; Irreversible = '서명 업데이트는 되돌릴 대상이 아님' }
}