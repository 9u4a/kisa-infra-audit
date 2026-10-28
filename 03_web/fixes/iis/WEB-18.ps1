# WEB-18 (상) 웹 서비스 WebDAV 비활성화 [IIS] — 조치 [fix: auto]
# F-R3: 진단(checks/iis/WEB-18.ps1)과 같은 위치 - 사이트 루트와 하위 application·virtual directory(Get-IisSiteConfigPaths) -
# 를 모두 확인해 WebDAV 저작이 켜진 곳을 끈다. webdav 섹션은 기본적으로 web.config 위임이 막혀 있어
# Set-FixWebConfigProperty 가 applicationHost.config <location path="사이트/하위경로"> 에 쓴다.

Invoke-FixIisConfigPaths -Filter "system.webServer/webdav/authoring" -Name "enabled" -Value $false -What "WebDAV 를 비활성화한" -IsVuln {
    param($v)
    $v -eq $true
}
