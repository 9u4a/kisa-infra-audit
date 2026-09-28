# D-14 (중) 데이터베이스의 주요 설정 파일, 비밀번호 파일 등의 접근 권한 적절성 [MySQL]
# 가이드 원문 "대상"에는 Oracle DB/PostgreSQL/Cubrid만 명시되어 있으나, 같은 항목의
# "점검 및 조치 사례" 본문에는 MySQL my.cnf 파일 권한(600/640) 절차가 그대로 포함되어 있다.
# 이는 가이드 자체의 대상 표기 누락으로 보고(deviation), 조치 방법이 실존하는 MySQL 설정 파일에도
# 동일하게 적용한다. 판단 기준: 양호 = 일반 사용자의 수정 권한 제거(권한 <= 640) / 취약 = 아님.
run_check() {
    f=$(mysql_config_path)
    if [ -z "$f" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="mysql 설정 파일(my.cnf)을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    check_owner_perm "$f" "root mysql" 640
}
