# W-02 (상) Guest 계정 비활성화 [fix: auto]
# checks/W-02.ps1 과 짝을 이루는 조치: 빌트인 Guest 계정(RID 501)을 비활성화한다.

$guest = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True and SID like 'S-1-5-%-501'" -ErrorAction SilentlyContinue
if (-not $guest) {
    $Global:FixStatus = "ERROR"
    $Global:FixDetail = "빌트인 Guest 계정(RID 501)을 조회하지 못함"
    $Global:FixEvidence = ""
    return
}

Set-FixLocalAccountDisabled -Name $guest.Name -Disabled $true
