# D-07 (중) root 권한으로 서비스 구동 제한 [MySQL]
# 판단 기준(가이드 원문): 양호 = DBMS가 root 계정/권한이 아닌 별도 계정으로 구동
#                        취약 = root 계정/권한으로 구동
# ps/pgrep 가 없는 최소 구성 이미지 대응을 위해 /proc 기반 프로세스 조회를 사용한다
# (03_web WEB-09 에서 검증된 패턴 재사용).
run_check() {
    pids=$(proc_pids_by_comm mysqld)
    if [ -z "$pids" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="mysqld 프로세스를 찾지 못함(/proc 기준) - 수동 확인 필요"; CHECK_EVIDENCE=""
        return
    fi
    evidence=""
    any_root=0
    for pid in $pids; do
        uid=$(proc_uid "$pid")
        evidence="$evidence
pid=$pid,uid=$uid"
        [ "$uid" = "0" ] && any_root=1
    done
    CHECK_EVIDENCE="$evidence"
    if [ "$any_root" -eq 1 ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="mysqld 프로세스가 root(uid 0) 권한으로 구동 중"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="mysqld 프로세스가 root가 아닌 계정으로 구동 중"
    fi
}
