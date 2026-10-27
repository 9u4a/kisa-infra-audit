# U-42 (상) 불필요한 RPC 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = 불필요한 RPC 서비스(가이드 명시 목록)가 비활성화된 경우
#                        취약 = 활성화된 경우
# 대상(가이드 원문): rpc.cmsd, rpc.ttdbserverd, sadmind, rusersd, walld, sprayd, rstatd,
#                    rpc.nisd, rexd, rpc.pcnfsd, rpc.statd, rpc.ypupdated, rpc.rquotad,
#                    kcms_server, cachefsd
# 전 Unix 계열 공통 로직: 프로세스 및 rpcinfo 등록 여부로 판정.

run_check() {
    pattern="rpc\.cmsd|rpc\.ttdbserverd|sadmind|rusersd|walld|sprayd|rstatd|rpc\.nisd|rexd|rpc\.pcnfsd|rpc\.statd|rpc\.ypupdated|rpc\.rquotad|kcms_server|cachefsd"

    check_service_disabled "불필요한 RPC(cmsd/ttdbserverd/sadmind/rusersd/walld/sprayd/rstatd/nisd/rexd/pcnfsd/statd/ypupdated/rquotad/kcms_server/cachefsd)" "$pattern"

    if command -v rpcinfo >/dev/null 2>&1; then
        # 로컬 portmapper 가 방화벽에 DROP 되면 rpcinfo 가 오래 기다리므로 시간 제한(lib/common.sh run_to)
        rpc_out=$(run_to 10 rpcinfo -p 2>/dev/null | grep -iE 'cmsd|ttdbserver|sadmind|rusersd|walld|sprayd|rstatd|nisd|rexd|pcnfsd|statd|ypupdated|rquotad|kcms|cachefsd')
        if [ -n "$rpc_out" ]; then
            CHECK_STATUS="VULN"
            CHECK_DETAIL="rpcinfo 에 불필요한 RPC 서비스가 등록되어 있음"
            CHECK_EVIDENCE="$CHECK_EVIDENCE
rpcinfo -p:
$rpc_out"
        fi
    fi
}
