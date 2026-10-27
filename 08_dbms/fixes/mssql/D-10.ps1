# D-10 (상) 원격에서 DB 서버로의 접속 제한 [MSSQL] — 조치 [fix: confirm]
# checks/mssql/D-10.ps1: 취약 = 모든 Windows 방화벽 프로필이 비활성화됨. 02_windows/fixes/W-64.ps1 과
# 같은 lib/Common.psm1 Enable-FixFirewallSafely 로 켜되, SQL Server 포트도 필수 허용 포트로 넘긴다 -
# 예전에는 DB 서버에서 방화벽만 켜 1433 접속을 끊을 수 있었다(사실상 서비스 중단). 포트는 현재 접속의
# TCP 포트(sys.dm_exec_connections)를 쓰고, 알 수 없으면(공유 메모리 접속 등) 기본 1433 으로 본다.
# 어떤 IP 만 허용할지는 스크립트가 알 수 없어(U-28류) 허용 범위 세분화는 수동으로 해야 한다.

$sqlPort = 1433
$p = Invoke-MssqlQuery -Sql "SET NOCOUNT ON; SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID;"
if ($Global:DbQueryOk) {
    $v = "$(@($p)[0])".Trim()
    if ($v -match '^\d+$' -and [int]$v -gt 0) { $sqlPort = [int]$v }
}

Enable-FixFirewallSafely -RequiredPorts @($sqlPort) -Note " - DB 포트(TCP $sqlPort)에 특정 IP 만 허용하는 세부 규칙은 별도로 수동 구성 필요"
