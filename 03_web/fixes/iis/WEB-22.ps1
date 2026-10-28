# WEB-22 (하) 에러 페이지 관리 [IIS] — 조치 [fix: auto]
# errorMode=Detailed(원격에도 상세 오류 노출)인 위치를 DetailedLocalOnly(로컬에서만 상세,
# IIS 기본값)로 되돌린다 - 원격에는 일반 오류만 노출되면서도 로컬 디버깅은 유지되는 안전한 값.
# F-R3: 진단(checks/iis/WEB-22.ps1)과 같은 위치 - 사이트 루트와 하위 application·virtual directory - 를 모두 고친다.

Invoke-FixIisConfigPaths -Filter "system.webServer/httpErrors" -Name "errorMode" -Value "DetailedLocalOnly" -What "errorMode 을 DetailedLocalOnly 로 되돌린" -IsVuln {
    param($v)
    "$v" -eq "Detailed"
}
