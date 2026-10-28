# D-20 (하) 인가되지 않은 Object Owner의 제한 [Oracle]
# 판단 기준(가이드 원문): 양호 = Object Owner가 SYS/SYSTEM/관리자 계정 등으로 제한된 경우
#                        취약 = 일반 사용자에게도 Object Owner가 존재하는 경우
# 애플리케이션 스키마가 정상적으로 Object 를 소유하는 구성이 흔해 완전 자동 판정은 어렵다
# - 소유자 목록을 증적으로 제공해 수동 검토한다.
# deviation: 가이드 원문의 정적 제외 목록 대신 dba_users.oracle_maintained='N' 조건을 사용한다
# (D-11/D-21과 동일한 이유 — Oracle 19c/23c 이후 추가된 내장 스키마가 정적 목록에 없어 증적에
# 노이즈가 섞이는 문제를 Docker 실기 테스트로 확인, 버전 무관하게 동작하도록 수정).
run_check() {
    # dba_objects 전체를 DISTINCT 하던 것을 사용자별 EXISTS(첫 행에서 멈춤)로 바꿨다 - 객체가 수백만 개인
    # 운영 DB 에서 전체 스캔·정렬 부하가 컸다(진단 검수 D-R12, S4). 결과(소유자 목록)는 같다.
    sql="SELECT u.username FROM dba_users u WHERE u.oracle_maintained = 'N' AND u.username NOT IN (SELECT grantee FROM dba_role_privs WHERE granted_role = 'DBA') AND EXISTS (SELECT 1 FROM dba_objects o WHERE o.owner = u.username) ORDER BY u.username;"
    out=$(oracle_query "$sql")
    rc=$?
    if [ $rc -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="Oracle 연결/쿼리 실패: $(head -1 "$DB_ERR_FILE" 2>/dev/null) $out"; CHECK_EVIDENCE="$out"
        return
    fi
    CHECK_EVIDENCE="$out"
    if [ -z "$out" ]; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="관리자/내장 계정 외 Object Owner가 없음"
    else
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="관리자/내장 계정 외 Object Owner가 존재함 - 인가된 애플리케이션 계정인지 수동 검토 필요"
    fi
}
