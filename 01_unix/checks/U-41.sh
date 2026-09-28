# U-41 (상) 불필요한 automountd 제거
# 판단 기준(가이드 원문): 양호 = automountd(autofs) 서비스 비활성화 / 취약 = 활성화
# 전 Unix 계열 공통 로직.

run_check() {
    check_service_disabled "automount/autofs" "automountd|autofs" "autofs"
}
