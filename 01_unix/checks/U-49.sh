# U-49 (상) DNS 보안 버전 패치
# 판단 기준(가이드 원문): 양호 = 주기적으로 패치를 관리하는 경우 / 취약 = 관리하지 않는 경우
# "주기적 관리 여부"는 운영 정책 문제라 자동 판정이 불가능하다.
# 자동화 범위: BIND(named) 설치·버전 확인 후 MANUAL 로 관리자 확인을 요청. 미설치 시 GOOD.

run_check() {
    if command -v named >/dev/null 2>&1; then
        v=$(named -v 2>/dev/null)
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="BIND(named)가 설치되어 있음 — 최신 버전/보안 패치 적용 여부 및 패치 관리 정책 존재 여부를 수동 확인 필요"
        CHECK_EVIDENCE="named -v: $v"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="DNS 서비스(BIND/named)가 설치되어 있지 않음"
        CHECK_EVIDENCE=""
    fi
}
