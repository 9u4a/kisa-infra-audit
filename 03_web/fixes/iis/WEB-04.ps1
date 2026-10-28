# WEB-04 (상) 웹 서비스 디렉터리 리스팅 방지 설정 [IIS] — 조치 [fix: auto]
# F-R3: 진단(checks/iis/WEB-04.ps1)과 같은 위치 - 사이트 루트와 하위 application·virtual directory(Get-IisSiteConfigPaths) -
# 를 모두 확인해 리스팅이 켜진 곳을 끈다(예전에는 사이트 루트만 고쳐 하위 재정의가 남으면 재검증 실패 → 원복).

Invoke-FixIisConfigPaths -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $false -What "디렉터리 리스팅을 비활성화한" -IsVuln {
    param($v)
    $v -eq $true
}
