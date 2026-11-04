# W-21 (상) 암호화되지 않는 FTP 서비스 비활성화 [fix: confirm]
# 변경: FTPSVC(FTP 서비스) 중지 + 시작 유형 사용 안 함
# checks/W-21.ps1: 양호 = FTP 미사용 또는 중지 상태

Disable-FixService -Name "FTPSVC"
