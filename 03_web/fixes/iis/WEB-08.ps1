# WEB-08 (하) 웹 서비스 파일 업로드 및 다운로드 용량 제한 [IIS] — 조치 [fix: confirm]
# 변경: IIS requestLimits maxAllowedContentLength 가 사실상 무제한(4000000000 이상)인 곳 → 기본값 30000000(사이트 루트·하위
# application/virtual directory)
# 1.5.0 A24: 진단(checks/iis/WEB-08.ps1)과 같은 위치 - 하위 application·virtual directory 의 재정의까지 고친다(예전에는 사이트
# 루트만 고쳐 하위 재정의가 남으면 재검증 실패 → 원복). WEB-04 와 같은 공통 함수(lib/Common.psm1 Invoke-FixIisConfigPaths).

Invoke-FixIisConfigPaths -Filter "system.webServer/security/requestFiltering/requestLimits" -Name "maxAllowedContentLength" -Value 30000000 -What "업로드 용량 제한을 기본값(30000000바이트)으로 되돌린" -IsVuln {
    param($v)
    $null -ne $v -and [int64]$v -ge 4000000000
}
