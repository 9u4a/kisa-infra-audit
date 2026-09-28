# U-39 (상) 불필요한 NFS 서비스 비활성화
# 판단 기준(가이드 원문): 양호 = 불필요한 NFS 관련 데몬이 비활성화된 경우
#                        취약 = 활성화된 경우
# 전 Unix 계열 공통 로직: NFS 서버 데몬(nfsd/nfs-server) 기준. NFS 클라이언트 마운트만 있는
# 경우는 별개이므로 서버 데몬 기준으로 판정한다.

run_check() {
    check_service_disabled "NFS 서버(nfsd/statd/lockd)" "nfsd|rpc\.statd|rpc\.lockd|rpc\.mountd" "nfs-server nfs-kernel-server rpc-statd nfslock"
}
