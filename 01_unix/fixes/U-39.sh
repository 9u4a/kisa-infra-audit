# U-39 (상) 불필요한 NFS 서비스 비활성화 — 조치
# 변경: nfs-server·nfs-kernel-server·rpc-statd·nfslock 서비스 정지·비활성화, nfsd·rpc.statd·rpc.lockd·rpc.mountd 프로세스 종료
# 원복: 일부 — systemd 서비스 상태는 되돌리지만, 직접 종료한 프로세스(inetd 계열 등)는 다시 띄우지 않음
# 영향: 실행 중인 NFS 서버 서비스 중지·nfsd 종료 — 이 서버의 NFS 공유를 마운트한 클라이언트 접근 끊김
run_fix() {
    fix_service_disable nfs-server nfs-kernel-server rpc-statd nfslock
    fix_kill_procs 'nfsd|rpc\.statd|rpc\.lockd|rpc\.mountd'
    FIX_STATUS="APPLIED"
    FIX_DETAIL="NFS 서버 관련 서비스(nfs-server/nfs-kernel-server/rpc-statd/nfslock)를 정지/비활성화함"
    FIX_EVIDENCE="systemctl disable nfs-server nfs-kernel-server rpc-statd nfslock"
}
