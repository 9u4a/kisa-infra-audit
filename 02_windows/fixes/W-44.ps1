# W-44 (상) 원격으로 액세스할 수 있는 레지스트리 경로 [fix: confirm]
# checks/W-44.ps1: 양호 = Remote Registry 서비스 중지

Disable-FixService -Name "RemoteRegistry"
