# WEB-02 (상) 취약한 비밀번호 사용 제한 [IIS]
# 판단 기준(가이드 원문): 양호 = 관리자 비밀번호가 암호화되어 있거나 유추하기 어려운 경우
#                        취약 = 암호화되어 있지 않거나 유추하기 쉬운 경우
# 자동화 범위: IIS는 Tomcat manager-gui 같은 단일 "관리자 계정"이 설정 파일에 평문으로
# 존재하지 않는다 - IIS 관리 계정은 Windows 로컬/도메인 계정(02_windows 대상) 또는 IIS Manager
# Users 기능의 별도 계정이며, 어느 쪽이든 비밀번호 강도를 파일에서 직접 판정할 수 없어 항상
# MANUAL 로 응답한다(가이드 원문에도 IIS 전용 점검 사례가 별도로 제공되지 않음).

if (-not (Test-IisAvailable)) {
    return New-CheckResult -Code "WEB-02" -Status "NA" -Detail "IIS(WebAdministration 모듈)가 설치되어 있지 않음"
}

return New-CheckResult -Code "WEB-02" -Status "MANUAL" -Detail "IIS는 설정 파일에 관리자 비밀번호가 저장되지 않음 - IIS Manager Users 계정 및 Windows 로컬 계정(02_windows 카테고리 참고)의 비밀번호 정책을 수동 확인 필요"
