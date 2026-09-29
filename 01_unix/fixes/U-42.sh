# U-42 (상) 불필요한 RPC 서비스 비활성화 — 조치
# 자동화 범위: 프로세스 종료 + systemd 유닛 비활성화까지만 수행한다. rpcbind 자체를 내리면
# 다른 정상 RPC 서비스(NFS 등)에도 영향을 줄 수 있어 개별 데몬만 대상으로 한다.
run_fix() {
    pattern="rpc\.cmsd|rpc\.ttdbserverd|sadmind|rusersd|walld|sprayd|rstatd|rpc\.nisd|rexd|rpc\.pcnfsd|rpc\.statd|rpc\.ypupdated|rpc\.rquotad|kcms_server|cachefsd"
    pkill -f "$pattern" 2>/dev/null
    fix_service_disable rpc.cmsd rpc.ttdbserverd sadmind rusersd rwalld rstatd rpc.nisd rexd rpc.pcnfsd rpc-statd.service rpc.ypupdated rpc.rquotad kcms_server cachefsd
    FIX_STATUS="APPLIED"
    FIX_DETAIL="가이드에서 나열한 불필요 RPC 데몬 프로세스를 종료하고 관련 systemd 유닛을 비활성화함"
    FIX_EVIDENCE="pkill -f '$pattern'"
}
