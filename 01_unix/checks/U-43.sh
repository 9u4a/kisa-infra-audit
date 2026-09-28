# U-43 (상) NIS, NIS+ 점검
# 판단 기준(가이드 원문): 양호 = NIS 서비스 비활성화(또는 불가피 시 NIS+ 사용) / 취약 = NIS 활성화
# 전 Unix 계열 공통 로직. NIS+ 여부까지는 자동 구분하지 않고, NIS(ypserv 등) 활성화만 판정.

run_check() {
    check_service_disabled "NIS(ypserv/ypbind/ypxfrd/yppasswdd/ypupdated)" "ypserv|ypbind|ypxfrd|rpc\.yppasswdd|rpc\.ypupdated" "ypserv ypbind"
}
