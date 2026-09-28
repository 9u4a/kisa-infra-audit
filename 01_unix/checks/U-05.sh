# U-05 (상) root 이외의 UID가 '0' 금지
# 판단 기준(가이드 원문): 양호 = root 계정과 동일한 UID를 갖는 계정이 존재하지 않는 경우
#                        취약 = root 계정과 동일한 UID를 갖는 계정이 존재하는 경우
# 자동화 범위: 전 Unix 계열 공통 (/etc/passwd 3번째 필드 기준이므로 환경 구분 불필요).

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    uid0_accounts=$(awk -F: '$3 == 0 {print $1}' "$passwd_file")
    uid0_count=$(printf '%s\n' "$uid0_accounts" | grep -c .)
    extra=$(printf '%s\n' "$uid0_accounts" | grep -v '^root$')

    if [ "$uid0_count" -le 1 ] && [ -z "$extra" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="UID 0 을 가진 계정이 root 뿐임"
        CHECK_EVIDENCE="UID=0: $uid0_accounts"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="root 이외에 UID 0 을 가진 계정이 존재함"
        CHECK_EVIDENCE="UID=0 계정 목록:
$uid0_accounts"
    fi
}
