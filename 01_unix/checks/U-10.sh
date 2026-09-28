# U-10 (중) 동일한 UID 금지
# 판단 기준(가이드 원문): 양호 = 동일한 UID로 설정된 사용자 계정이 존재하지 않는 경우
#                        취약 = 동일한 UID로 설정된 사용자 계정이 존재하는 경우
# 전 Unix 계열 공통 로직 (/etc/passwd 3번째 필드 기준이므로 환경 구분 불필요).

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    dup_uids=$(awk -F: '{print $3}' "$passwd_file" | sort -n | uniq -d)
    if [ -z "$dup_uids" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="중복된 UID를 가진 계정이 존재하지 않음"
        CHECK_EVIDENCE=""
    else
        detail_accounts=$(awk -F: -v uids="$dup_uids" '
            BEGIN { n = split(uids, arr, "\n"); for (i=1;i<=n;i++) target[arr[i]]=1 }
            ($3 in target) { print $1":"$3 }
        ' "$passwd_file")
        CHECK_STATUS="VULN"
        CHECK_DETAIL="동일한 UID를 사용하는 계정이 존재함"
        CHECK_EVIDENCE="$detail_accounts"
    fi
}
