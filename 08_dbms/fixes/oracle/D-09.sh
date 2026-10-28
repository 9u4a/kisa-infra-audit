# D-09 (중) 일정 횟수의 로그인 실패 시 이에 대한 잠금정책 설정 [Oracle] — 조치 [fix: confirm — 1.3.0 재분류, guide.json deviation 참고]
# 조치 후속 F-R6: 진단(checks/oracle/D-09.sh)이 OPEN 계정이 쓰는 사용자 정의 프로파일까지 보므로, 조치도 같은 범위의
# FAILED_LOGIN_ATTEMPTS=UNLIMITED 프로파일을 모두 고친다(lib/common.sh oracle_fix_profile_limits - DEFAULT 먼저, 상속으로
# 해소되면 건너뜀, 원복 SQL 은 조치 직전 값 그대로).
run_fix() {
    oracle_fix_profile_limits "'FAILED_LOGIN_ATTEMPTS'" "FAILED_LOGIN_ATTEMPTS 5"
}
