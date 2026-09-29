# WEB-24 (중) 별도의 업로드 경로 사용 및 권한 설정 [IIS]
# 판단 기준(가이드 원문): 양호 = 별도 업로드 경로 사용 및 일반 사용자 접근 권한 미부여
#                        취약 = 별도 경로 미사용 또는 일반 사용자 접근 권한 부여
# 자동화 범위: 업로드 디렉터리는 애플리케이션마다 임의로 지정되어 표준 설정 키가 없어(가이드
# 원문도 "웹 서비스 외부에 업로드 디렉터리를 생성"이라는 절차만 안내) 자동 판정 불가 - Apache/
# Nginx/Tomcat 구현과 동일하게 항상 MANUAL 로 응답한다(03_web/CLAUDE.md 참고).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-24" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}
return New-CheckResult -Code "WEB-24" -Status "MANUAL" -Detail "업로드 경로는 애플리케이션마다 상이해 자동 판정 불가 - 웹 서비스 외부의 별도 디렉터리 사용 여부와 IIS 구동 계정만 쓰기 권한을 갖는지 수동 확인 필요"
