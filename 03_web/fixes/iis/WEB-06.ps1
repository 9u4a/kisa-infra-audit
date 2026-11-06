# WEB-06 (상) 웹 서비스 상위 디렉터리 접근 제한 설정 [IIS] — 조치 [fix: confirm]
# 변경: IIS system.webServer/asp enableParentPaths=true → false(사이트 루트·하위 application/virtual directory 중 켜진 곳)
# 1.5.0 A24: 진단(checks/iis/WEB-06.ps1)과 같은 위치 - 사이트 루트와 하위 application·virtual directory(Get-IisSiteConfigPaths)
# 를 모두 확인해 켜진 곳을 끈다(예전에는 사이트 루트만 고쳐 하위 재정의가 남으면 재검증 실패 → 원복). WEB-04 와 같은 공통 함수.

Invoke-FixIisConfigPaths -Filter "system.webServer/asp" -Name "enableParentPaths" -Value $false -What "상위 디렉터리 접근(enableParentPaths)을 비활성화한" -IsVuln {
    param($v)
    $v -eq $true
}
