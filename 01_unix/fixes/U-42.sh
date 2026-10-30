# U-42 (상) 불필요한 RPC 서비스 비활성화 — 조치
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
# 자동화 범위: 프로세스 종료 + systemd 유닛 비활성화까지만 수행한다. rpcbind 자체를 내리면
# 다른 정상 RPC 서비스(NFS 등)에도 영향을 줄 수 있어 개별 데몬만 대상으로 한다.
run_fix() {
    pattern="rpc\.cmsd|rpc\.ttdbserverd|sadmind|rusersd|walld|sprayd|rstatd|rpc\.nisd|rexd|rpc\.pcnfsd|rpc\.statd|rpc\.ypupdated|rpc\.rquotad|kcms_server|cachefsd"
    # U-C2(1.4.0): 유닛 상태(enabled/active)를 먼저 기록·정지한 뒤 남은 프로세스를 종료한다. 예전에는 프로세스를 먼저
    # 죽여, 그 프로세스가 유닛의 주 프로세스면 기록되는 상태가 이미 "inactive" 라 원복해도 서비스가 다시 뜨지 않았다.
    fix_service_disable rpc.cmsd rpc.ttdbserverd sadmind rusersd rwalld rstatd rpc.nisd rexd rpc.pcnfsd rpc-statd.service rpc.ypupdated rpc.rquotad kcms_server cachefsd
    fix_kill_procs "$pattern"
    FIX_STATUS="APPLIED"
    FIX_DETAIL="가이드에서 나열한 불필요 RPC 데몬 프로세스를 종료하고 관련 systemd 유닛을 비활성화함"
    FIX_EVIDENCE="실행 파일 이름 ~ '$pattern' 프로세스 종료"
}
