# U-31 (중) 홈디렉토리 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 홈 디렉토리 소유자가 해당 계정이고 타 사용자 쓰기 권한이 없는 경우
#                        취약 = 그 외
# 전 Unix 계열 공통 로직: 로그인 가능한 계정 기준으로 검사.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    accounts=$(awk -F: '$7 !~ /(nologin|false)$/ {print $1":"$6}' "$passwd_file")
    violations=""
    evidence=""
    checked=0

    old_ifs=$IFS; IFS='
'
    for entry in $accounts; do
        IFS=$old_ifs
        name=${entry%%:*}
        home=${entry#*:}
        [ -d "$home" ] || continue
        checked=$((checked + 1))
        owner=$(stat -c '%U' "$home" 2>/dev/null)
        evidence="$evidence
$(ls -ld "$home" 2>/dev/null)"
        other_write=$(find "$home" -maxdepth 0 -perm -0002 2>/dev/null)
        if [ "$owner" != "$name" ] || [ -n "$other_write" ]; then
            violations="$violations $home(owner=$owner)"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="검사 대상 홈 디렉토리가 없음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="검사한 홈 디렉토리(${checked}개)가 모두 소유자 일치 및 타 사용자 쓰기 권한 제거 기준을 충족함"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="소유자가 다르거나 타 사용자 쓰기 권한이 부여된 홈 디렉토리가 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}
