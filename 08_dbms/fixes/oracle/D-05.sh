# D-05 (중) 비밀번호 재사용에 대한 제약 설정 [Oracle] — 조치 [fix: auto]
# 조치 후속 F-R6: 진단(checks/oracle/D-05.sh)이 OPEN 계정이 쓰는 사용자 정의 프로파일까지 보므로, 조치도 같은 범위의
# 미설정 프로파일을 모두 고친다(lib/common.sh oracle_fix_profile_limits - DEFAULT 먼저, 상속으로 해소되면 건너뜀,
# 원복 SQL 은 조치 직전 값 그대로).
run_fix() {
    oracle_fix_profile_limits "'PASSWORD_REUSE_TIME','PASSWORD_REUSE_MAX'" "PASSWORD_REUSE_TIME 365 PASSWORD_REUSE_MAX 5"
}
