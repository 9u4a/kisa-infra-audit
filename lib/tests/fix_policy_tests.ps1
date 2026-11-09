# lib/tests/fix_policy_tests.ps1 - 조치 정책 모드(1.6.0 G-01·G-02·G-03) 단위 테스트(PowerShell 쪽)
# 정책 파일 파서(Read-FixPolicy)·항목 판정(Get-FixPolicyDecision)·옵션 검사(Test-FixPolicyArgs) 를 임시 파일로 확인하고,
# Windows 에서는 02_windows/fix.ps1 을 정책 모드 dry-run 으로 실행해 POLICY_SKIPPED·audit.txt·exit 2 를 확인한다.
# 시스템을 바꾸지 않는다(dry-run 은 출력 폴더만 만든다 - 임시 폴더에 만들고 지운다). pwsh 7(ubuntu)·Windows PowerShell 5.1 모두에서 돈다.
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Import-Module (Join-Path $Repo "lib/Common.psm1") -Force

$script:fail = 0; $script:pass = 0
function Assert-True([string]$Name, [bool]$Cond, [string]$Info = "") {
    if ($Cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $Name $Info" }
}
function Assert-Rejected([string]$Name, $Res, [string]$Pattern) {
    $hit = @($Res.Errors | Where-Object { $_ -match $Pattern })
    Assert-True $Name ((-not $Res.Ok) -and $hit.Count -gt 0) ("(Ok=$($Res.Ok), 기대 패턴 '$Pattern', 오류: " + ($Res.Errors -join ' | ') + ")")
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "kisa_policy_test_$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:n = 0
function New-PolicyFile([string[]]$Lines, [switch]$Bom, [switch]$Crlf) {
    $script:n++
    $p = Join-Path $tmp "policy_$($script:n).txt"
    $sep = if ($Crlf) { "`r`n" } else { "`n" }
    $enc = if ($Bom) { New-Object System.Text.UTF8Encoding($true) } else { $utf8NoBom }
    [System.IO.File]::WriteAllText($p, (($Lines -join $sep) + $sep), $enc)
    return $p
}

$known02 = @((Get-Content -Raw -Encoding UTF8 (Join-Path $Repo "02_windows/guide.json") | ConvertFrom-Json).items | ForEach-Object { $_.code })
$today = "2026-11-09"
function Read-P([string]$Path, [string]$HostName = "web01", [string]$Cat = "02") {
    return (Read-FixPolicy -Path $Path -CategoryNum $Cat -KnownCodes $known02 -HostName $HostName -Today $today)
}

try {
    # ---- 정상 ----
    $ok = New-PolicyFile @("# 주석", "", "category=02", "expires=2026-12-31", "approver=홍길동", "  W-07  ", "W-17:irreversible", "W-13", "", "[host:WEB01]", "-W-13", "", "[host:*]", "-W-07")
    $r = Read-P $ok "web01"
    Assert-True "정상 파일 Ok" $r.Ok ($r.Errors -join ' | ')
    Assert-True "approver" ($r.Approver -eq "홍길동") $r.Approver
    Assert-True "category/expires" ($r.Category -eq "02" -and $r.Expires -eq "2026-12-31")
    Assert-True "승인 코드 3개" ($r.Codes.Count -eq 3)
    Assert-True "irreversible 플래그" ($r.Codes["W-17"] -and -not $r.Codes["W-07"])
    Assert-True "호스트 구역(대소문자 무시)" ($r.HostSection -eq "WEB01") $r.HostSection
    Assert-True "호스트 제외 목록" (@($r.Excluded) -join "," -eq "W-13") (@($r.Excluded) -join ",")
    Assert-True "SHA-256" ($r.Sha256 -eq (Get-FileHash -LiteralPath $ok -Algorithm SHA256).Hash.ToLowerInvariant() -and $r.Sha256 -cmatch '^[0-9a-f]{64}$')
    Assert-True "절대 경로" ([System.IO.Path]::IsPathRooted($r.Path))
    $r2 = Read-P $ok "db01"
    Assert-True "[host:*] 적용" ($r2.Ok -and $r2.HostSection -eq "*" -and (@($r2.Excluded) -join ",") -eq "W-07") "$($r2.HostSection) / $(@($r2.Excluded) -join ',')"

    # ---- 판정 ----
    $fixPlain = Join-Path $tmp "plain.ps1"; [System.IO.File]::WriteAllText($fixPlain, "# W-07 test`n# 변경: 값 0`n", $utf8NoBom)
    $fixRb = Join-Path $tmp "rb.ps1"; [System.IO.File]::WriteAllText($fixRb, "# X`n# 변경: 값`n# 원복: 불가 — 테스트`n", $utf8NoBom)
    $fixImp = Join-Path $tmp "imp.ps1"; [System.IO.File]::WriteAllText($fixImp, "# X`n# 변경: 값`n# 영향: 서비스 중지 — 테스트`n", $utf8NoBom)
    $d = Get-FixPolicyDecision -Policy $r -Code "W-07" -FixFile $fixPlain
    Assert-True "승인 항목" $d.Approved $d.Reason
    $d = Get-FixPolicyDecision -Policy $r -Code "W-59" -FixFile $fixPlain
    Assert-True "정책에 없는 항목 = 정책 미승인" ((-not $d.Approved) -and $d.Reason -eq "정책 미승인") $d.Reason
    $d = Get-FixPolicyDecision -Policy $r -Code "W-13" -FixFile $fixPlain
    Assert-True "호스트 제외 = 정책 미승인" ((-not $d.Approved) -and $d.Reason.StartsWith("정책 미승인")) $d.Reason
    $d = Get-FixPolicyDecision -Policy $r2 -Code "W-07" -FixFile $fixRb
    Assert-True "[host:*] 제외" (-not $d.Approved) $d.Reason
    $d = Get-FixPolicyDecision -Policy $r2 -Code "W-13" -FixFile $fixRb
    Assert-True "원복 머리말 + 플래그 없음 = 거부" ((-not $d.Approved) -and $d.Reason -match '^irreversible 플래그 필요: 원복: 불가') $d.Reason
    $d = Get-FixPolicyDecision -Policy $r2 -Code "W-13" -FixFile $fixImp
    Assert-True "영향 머리말 + 플래그 없음 = 거부" ((-not $d.Approved) -and $d.Reason -match '^irreversible 플래그 필요: 영향: 서비스 중지') $d.Reason
    $d = Get-FixPolicyDecision -Policy $r -Code "W-17" -FixFile $fixImp
    Assert-True "irreversible 플래그 있으면 승인" $d.Approved $d.Reason
    # 실제 조치 파일 머리말(G-02): W-17 은 원복·영향 둘 다, W-07 은 없음
    $d = Get-FixPolicyDecision -Policy $r2 -Code "W-13" -FixFile (Join-Path $Repo "02_windows/fixes/W-17.ps1")
    Assert-True "실제 W-17 머리말(원복+영향)" ($d.Reason -match '원복: .* / 영향: ') $d.Reason
    Assert-True "실제 W-07 머리말 없음" ((Get-FixRollbackNote -File (Join-Path $Repo "02_windows/fixes/W-07.ps1") -Label "영향") -eq "")

    # ---- BOM / CRLF ----
    $bc = New-PolicyFile @("category=02", "expires=2026-12-31", "approver=김철수", "W-07", "[host:*]") -Bom -Crlf
    $r = Read-P $bc
    Assert-True "BOM+CRLF Ok" $r.Ok ($r.Errors -join ' | ')
    Assert-True "BOM+CRLF 값에 \r 없음" ($r.Approver -eq "김철수" -and $r.Category -eq "02")
    Assert-True "BOM+CRLF 코드" ($r.Codes.ContainsKey("W-07"))

    # ---- 만료 경계 ----
    $r = Read-P (New-PolicyFile @("category=02", "expires=$today", "approver=a", "W-07", "[host:*]"))
    Assert-True "expires=오늘 은 유효" $r.Ok ($r.Errors -join ' | ')

    # ---- 거부 ----
    Assert-Rejected "category 불일치" (Read-P (New-PolicyFile @("category=07", "expires=2026-12-31", "approver=a", "W-07", "[host:*]"))) '^줄 1: .*실행 카테고리\(02\)'
    Assert-Rejected "허용되지 않는 category" (Read-P (New-PolicyFile @("category=04", "expires=2026-12-31", "approver=a", "[host:*]"))) '^줄 1: category=04'
    Assert-Rejected "만료" (Read-P (New-PolicyFile @("category=02", "expires=2026-11-08", "approver=a", "W-07", "[host:*]"))) '^줄 2: 정책이 만료됨'
    Assert-Rejected "날짜 형식" (Read-P (New-PolicyFile @("category=02", "expires=2026-13-01", "approver=a", "[host:*]"))) '^줄 2: .*YYYY-MM-DD'
    Assert-Rejected "날짜 형식(구분자)" (Read-P (New-PolicyFile @("category=02", "expires=2026/12/31", "approver=a", "[host:*]"))) 'YYYY-MM-DD'
    Assert-Rejected "코드 중복" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-07", "W-07:irreversible", "[host:*]"))) '^줄 5: 코드 W-07 중복\(처음: 줄 4\)'
    Assert-Rejected "없는 코드" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-99", "[host:*]"))) "^줄 4: guide.json 에 없는 코드 'W-99'"
    Assert-Rejected "다른 카테고리 코드" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "U-01", "[host:*]"))) "없는 코드 'U-01'"
    Assert-Rejected "소문자 코드" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "w-07", "[host:*]"))) "없는 코드 'w-07'"
    Assert-Rejected "알 수 없는 키" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "owner=b", "[host:*]"))) "^줄 4: 알 수 없는 키 'owner'"
    Assert-Rejected "키 중복" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "approver=b", "[host:*]"))) '^줄 4: approver= 중복'
    Assert-Rejected "approver 비어 있음" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=", "[host:*]"))) '^줄 3: approver= 가 비어'
    Assert-Rejected "approver 없음" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "[host:*]"))) 'approver= 가 없음'
    Assert-Rejected "머리말 키가 구역 뒤" (Read-P (New-PolicyFile @("category=02", "approver=a", "[host:*]", "expires=2026-12-31"))) '^줄 4: \[host:\] 구역에는'
    Assert-Rejected "알 수 없는 표시" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-07:force", "[host:*]"))) "^줄 4: 알 수 없는 표시"
    Assert-Rejected "구역에 승인 코드" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "[host:web01]", "W-07"))) '^줄 5: \[host:\] 구역에는'
    Assert-Rejected "구역 제외 코드 오타" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-07", "[host:*]", "-W-99"))) "^줄 6: guide.json 에 없는 코드"
    Assert-Rejected "구역 중복" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "[host:web01]", "[host:WEB01]"))) '^줄 5: \[host:WEB01\] 구역 중복'
    Assert-Rejected "알 수 없는 구역" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "[hosts:web01]"))) '^줄 4: 알 수 없는 구역'
    Assert-Rejected "해석 불가 줄" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-07 W-08", "[host:*]"))) '^줄 4: 해석할 수 없는 줄'
    Assert-Rejected "호스트 미등록" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-07", "[host:web01]")) "db01") '정책에 없는 호스트: db01'
    Assert-Rejected "구역 없음" (Read-P (New-PolicyFile @("category=02", "expires=2026-12-31", "approver=a", "W-07"))) '정책에 없는 호스트'
    Assert-Rejected "파일 없음" (Read-P (Join-Path $tmp "nope.txt")) '정책 파일을 읽을 수 없음'
    $multi = Read-P (New-PolicyFile @("category=07", "expires=2020-01-01", "approver=a", "W-99", "[host:*]"))
    Assert-True "오류를 모두 모아 보고" (@($multi.Errors).Count -ge 3) ($multi.Errors -join ' | ')

    # ---- 옵션 검사 ----
    Assert-True "-Policy 단독 거부" (-not (Test-FixPolicyArgs -Policy "p.txt" -Operator "" 6>$null))
    Assert-True "-Policy + 공백 -Operator 거부" (-not (Test-FixPolicyArgs -Policy "p.txt" -Operator "  " 6>$null))
    Assert-True "-Operator 단독 거부" (-not (Test-FixPolicyArgs -Policy "" -Operator "kim" 6>$null))
    Assert-True "-Operator 제어 문자 거부" (-not (Test-FixPolicyArgs -Policy "p.txt" -Operator "kim`nmode=apply" 6>$null))
    Assert-True "둘 다 있으면 통과" (Test-FixPolicyArgs -Policy "p.txt" -Operator "kim")
    Assert-True "둘 다 없으면 통과" (Test-FixPolicyArgs -Policy "" -Operator "")

    # ---- 진입점 dry-run(Windows 전용 - 시스템을 바꾸지 않음) ----
    if ($env:OS -eq "Windows_NT") {
        $ps = (Get-Process -Id $PID).Path
        $fixPs1 = Join-Path $Repo "02_windows/fix.ps1"
        $hostName = $env:COMPUTERNAME
        $res = Join-Path $tmp "result.json"
        $items = @("W-07", "W-17", "W-59", "W-13", "W-32") | ForEach-Object { @{ code = $_; status = "VULN"; detail = "t"; evidence = "" } }
        $obj = @{ tool_version = "t"; guide_version = "t"; category = "Windows 서버"; host = $hostName; env = "t"; generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); items = $items }
        [System.IO.File]::WriteAllText($res, ($obj | ConvertTo-Json -Depth 5), $utf8NoBom)
        $pol = New-PolicyFile @("category=02", "expires=2099-12-31", "approver=CI 승인자", "W-07", "W-17", "W-13", "[host:$hostName]", "-W-13")
        $out = Join-Path $tmp "out_dry"
        $log = & $ps -NoProfile -NonInteractive -File $fixPs1 -ResultJson $res -OutBase $out -Policy $pol -Operator "ci-tester" 2>&1 | Out-String
        $rc = $LASTEXITCODE
        Assert-True "dry-run exit 0" ($rc -eq 0) "rc=$rc`n$log"
        $runDir = Get-ChildItem -Path $out -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        Assert-True "dry-run 출력 폴더" ([bool]$runDir) $log
        if ($runDir) {
            $rows = @(Get-Content -Encoding UTF8 (Join-Path $runDir "changes.log") | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object { $c = $_ -split "`t"; [PSCustomObject]@{ Code = $c[1]; Result = $c[3]; Detail = $c[4] } })
            $byCode = @{}; foreach ($x in $rows) { $byCode[$x.Code] = $x }
            Assert-True "W-17 irreversible 필요" ($byCode["W-17"] -and $byCode["W-17"].Result -eq "POLICY_SKIPPED" -and $byCode["W-17"].Detail -match '^irreversible 플래그 필요: 원복: ') "$($byCode['W-17'].Result) $($byCode['W-17'].Detail)"
            Assert-True "W-59 정책 미승인" ($byCode["W-59"] -and $byCode["W-59"].Result -eq "POLICY_SKIPPED" -and $byCode["W-59"].Detail -eq "정책 미승인")
            Assert-True "W-13 호스트 제외" ($byCode["W-13"] -and $byCode["W-13"].Result -eq "POLICY_SKIPPED" -and $byCode["W-13"].Detail -match '^정책 미승인\(호스트 제외')
            Assert-True "W-32(manual) 정책 미승인" ($byCode["W-32"] -and $byCode["W-32"].Result -eq "POLICY_SKIPPED")
            Assert-True "W-07 적용 예정 표시" ($log -match 'W-07' -and $log -match '정책 승인 - 적용 예정') $log
            $audit = Join-Path $runDir "audit.txt"
            Assert-True "audit.txt 있음" (Test-Path $audit)
            if (Test-Path $audit) {
                $kv = @{}; foreach ($l in (Get-Content -Encoding UTF8 $audit)) { $i = $l.IndexOf("="); if ($i -gt 0) { $kv[$l.Substring(0, $i)] = $l.Substring($i + 1) } }
                foreach ($k in @("operator", "login_user", "approver", "policy_file", "policy_sha256", "policy_expires", "started_at", "host", "category", "mode", "finished_at", "policy_skipped", "failed_codes")) {
                    Assert-True "audit $k" ($kv.ContainsKey($k)) ($kv.Keys -join ",")
                }
                Assert-True "audit 값" ($kv["operator"] -eq "ci-tester" -and $kv["approver"] -eq "CI 승인자" -and $kv["mode"] -eq "dry-run" -and $kv["category"] -eq "02" -and $kv["policy_skipped"] -eq "4" -and $kv["preview"] -eq "1") (($kv.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; ")
                Assert-True "audit sha256" ($kv["policy_sha256"] -eq (Get-FileHash -LiteralPath $pol -Algorithm SHA256).Hash.ToLowerInvariant())
                Assert-True "audit started_at ISO 8601" ($kv["started_at"] -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$') $kv["started_at"]
                $head = @(Get-Content -Encoding UTF8 (Join-Path $runDir "changes.log") -TotalCount 12)
                Assert-True "changes.log 머리에 감사 기록" (@($head | Where-Object { $_ -eq "# operator=ci-tester" }).Count -eq 1) ($head -join "`n")
            }
        }
        # 거부: 아무것도 만들지 않고 exit 2
        $cases = @(
            @{ Name = "-Operator 단독"; Args = @("-Operator", "x") },
            @{ Name = "-Policy 단독"; Args = @("-Policy", $pol) },
            @{ Name = "만료된 정책"; Args = @("-Policy", (New-PolicyFile @("category=02", "expires=2020-01-01", "approver=a", "W-07", "[host:*]")), "-Operator", "x") },
            @{ Name = "다른 카테고리 정책"; Args = @("-Policy", (New-PolicyFile @("category=07", "expires=2099-12-31", "approver=a", "[host:*]")), "-Operator", "x") },
            @{ Name = "호스트 미등록"; Args = @("-Policy", (New-PolicyFile @("category=02", "expires=2099-12-31", "approver=a", "W-07", "[host:no-such-host-x]")), "-Operator", "x") }
        )
        $k = 0
        foreach ($c in $cases) {
            $k++
            $o = Join-Path $tmp "out_rej$k"
            $a = @("-NoProfile", "-NonInteractive", "-File", $fixPs1, "-ResultJson", $res, "-OutBase", $o) + $c.Args
            $l = & $ps @a 2>&1 | Out-String
            Assert-True "진입점 거부: $($c.Name) exit 2" ($LASTEXITCODE -eq 2 -and -not (Test-Path $o)) "rc=$LASTEXITCODE`n$l"
        }
    } else {
        Write-Host "(Windows 가 아니라 진입점 dry-run 검사는 건너뜀)"
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

if ($script:fail -gt 0) { Write-Host "FAIL: fix_policy_tests ($($script:fail) 실패 / $($script:pass) 통과)"; exit 1 }
Write-Host "PASS: fix_policy_tests ($($script:pass) 검사)"
exit 0
