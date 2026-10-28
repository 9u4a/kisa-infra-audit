# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [Oracle] — 조치 [fix: confirm]
# ALTER PROFILE 은 동적으로 즉시 적용된다(인스턴스 재시작 불필요).
# 주의(Docker 실기 테스트로 발견): "LIMIT ... DEFAULT" 로 원복하면 Oracle의 실제 내장 기본값으로
# 돌아가는데, 최신 버전(23ai/26ai)의 DEFAULT 프로파일 내장 기본값 자체가 UNLIMITED/NULL 이
# 아닐 수 있어 "DEFAULT" 키워드만으로는 조치 이전 값을 정확히 복원하지 못할 수 있다. 조치 전
# 실제 현재 값을 조회해 그 값 그대로 복원하도록 원복 SQL을 구성한다.
# 조치 후속 F-R6: 진단(checks/oracle/D-03.sh)이 OPEN 계정이 쓰는 사용자 정의 프로파일까지 보므로, 조치도 같은 범위의
# 미설정 프로파일을 모두 고친다(lib/common.sh oracle_fix_profile_limits - DEFAULT 먼저, 상속으로 해소되면 건너뜀).
run_fix() {
    oracle_fix_profile_limits "'PASSWORD_LIFE_TIME','PASSWORD_VERIFY_FUNCTION'" "PASSWORD_LIFE_TIME 90 PASSWORD_VERIFY_FUNCTION ora12c_verify_function"
}
