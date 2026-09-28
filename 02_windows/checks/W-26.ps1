# W-26 (상) RDS(Remote Data Services) 제거
# 판단 기준(가이드 원문): 양호 조건에 "Windows 2008 이상 버전을 사용하는 경우" 포함
# 가이드상 대상 자체가 Windows NT/2000/2003 뿐이며, 0.2.0 지원 범위(2012 R2 이상)는 전부
# 이 양호 조건에 해당하므로 NA 로 처리한다 (레거시 시스템은 향후 마이너 버전에서 지원 검토).

return New-CheckResult -Code "W-26" -Status "NA" -Detail "가이드 대상(Windows NT/2000/2003) 이후 버전이라 해당 없음 (Windows 2008 이상은 양호 조건에 해당)"
