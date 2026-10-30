# U-41 (상) 불필요한 automountd 제거
# 판단 기준(가이드 원문): 양호 = automountd(autofs) 서비스 비활성화 / 취약 = 활성화
# 전 Unix 계열 공통 로직.

run_check() {
    # U-C1(1.4.0): 실제 autofs 데몬의 실행 파일은 /usr/sbin/automount(Linux)·automountd(Solaris)다. 예전 "automountd|autofs" 는
    # pgrep -f 로 명령줄의 pid 파일 경로(autofs.pid)에 우연히 맞았을 뿐이라, 실행 파일 이름 기준으로 automount 를 넣었다.
    check_service_disabled "automount/autofs" "automount|autofs" "autofs"
}
