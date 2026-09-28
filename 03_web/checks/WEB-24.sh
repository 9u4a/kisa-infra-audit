# WEB-24 (중) 별도의 업로드 경로 사용 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 별도의 업로드 경로 사용 + 일반 사용자 접근 권한 미부여
#                        취약 = 별도 경로 미사용 또는 접근 권한 부여됨
# "업로드 경로"는 애플리케이션 구성에 따라 달라 설정 파일만으로 자동 판정이 불가능하다.

run_check() {
    detect_web_engines
    if [ -z "$WEB_ENGINES" ]; then
        CHECK_STATUS="NA"; CHECK_DETAIL="설치된 웹 엔진을 찾지 못함"; CHECK_EVIDENCE=""
        return
    fi
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="업로드 경로는 애플리케이션 구성에 따라 달라 설정 파일만으로 자동 판정할 수 없음 — 별도 경로 사용 여부 및 해당 경로 권한(750 이하 권장)을 수동 확인 필요"
    CHECK_EVIDENCE="감지된 엔진: $WEB_ENGINES"
}
