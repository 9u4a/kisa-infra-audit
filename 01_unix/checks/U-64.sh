# U-64 (상) 주기적 보안 패치 및 벤더 권고사항 적용
# 판단 기준(가이드 원문): 양호 = 패치 적용 정책을 수립하여 주기적으로 관리하는 경우
#                        취약 = 정책 미수립 또는 미관리
# "정책 수립 및 주기적 관리 여부"는 운영 절차이므로 자동 판정이 불가능하다.
# 자동화 범위: 현재 OS/커널 버전 정보만 수집해 MANUAL 로 제공 (관리자가 최신/EOL 여부 확인).

run_check() {
    evidence="uname -a: $(uname -a 2>/dev/null)"
    if command -v hostnamectl >/dev/null 2>&1; then
        evidence="$evidence
$(hostnamectl 2>/dev/null)"
    fi
    if [ -f /etc/os-release ]; then
        evidence="$evidence
/etc/os-release:
$(cat /etc/os-release 2>/dev/null)"
    fi

    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="패치 관리 정책 수립·이행 여부는 운영 절차 확인이 필요해 자동 판정할 수 없음. 현재 OS/커널 버전을 근거로 EOL 여부 및 최신 패치 적용 여부를 수동 확인 필요"
    CHECK_EVIDENCE="$evidence"
}
