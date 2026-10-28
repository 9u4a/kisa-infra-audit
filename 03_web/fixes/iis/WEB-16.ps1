# WEB-16 (중) 웹 서비스 헤더 정보 노출 제한 [IIS] — 조치 [fix: auto]
# F-R3: 진단(checks/iis/WEB-16.ps1)은 서버 전역 값과 함께 사이트별 유효 값(사이트 web.config 재정의)을 본다.
# 조치도 같은 순서로 - 서버 전역을 true 로 바꾼 뒤 재정의한 사이트를 고친다(lib/Common.psm1 Invoke-FixIisRemoveServerHeader,
# 02_windows W-33 과 공용).

Invoke-FixIisRemoveServerHeader
