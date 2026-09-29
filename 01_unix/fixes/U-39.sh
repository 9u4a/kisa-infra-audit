# U-39 (상) 불필요한 NFS 서비스 비활성화 — 조치
run_fix() {
    fix_service_disable nfs-server nfs-kernel-server rpc-statd nfslock
    pkill -f 'nfsd|rpc\.statd|rpc\.lockd|rpc\.mountd' 2>/dev/null
    FIX_STATUS="APPLIED"
    FIX_DETAIL="NFS 서버 관련 서비스(nfs-server/nfs-kernel-server/rpc-statd/nfslock)를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable nfs-server nfs-kernel-server rpc-statd nfslock"
}
