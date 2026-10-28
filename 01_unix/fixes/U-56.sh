# U-56 (하) FTP 서비스 접근 제어 설정 — 조치
# check(U-56)가 ftpusers(계정 제한)를 IP 접근 제어로 인정하지 않게 되면서(진단 검수 U-R15) 예전 조치(ftpusers 에 root
# 추가)로는 판정이 바뀌지 않는다. 허용할 IP/호스트는 조직 정책이라 자동으로 정할 수 없으므로 바꾸지 않고 안내만 한다.
run_fix() {
    FIX_STATUS="ERROR"
    FIX_DETAIL="허용할 IP/호스트를 알 수 없어 자동 조치 불가 - proftpd 는 <Limit LOGIN> 에 Allow from <IP>/DenyAll, vsftpd 는 tcp_wrappers=YES + hosts.allow/hosts.deny 의 vsftpd 규칙, 또는 방화벽으로 접속 IP 를 제한할 것"
    FIX_EVIDENCE=""
}
