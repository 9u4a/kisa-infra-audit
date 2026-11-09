# W-44 (상) 원격으로 액세스할 수 있는 레지스트리 경로 [fix: confirm]
# 변경: RemoteRegistry 서비스 중지 + 시작 유형 사용 안 함
# 영향: 실행 중인 RemoteRegistry 서비스 중지·사용 안 함 — 원격 레지스트리를 쓰는 관리·모니터링 도구 동작 중단
# checks/W-44.ps1: 양호 = Remote Registry 서비스 중지

Disable-FixService -Name "RemoteRegistry"
