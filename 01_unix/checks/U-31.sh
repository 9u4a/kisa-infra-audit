# U-31 (중) 홈디렉토리 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 홈 디렉토리 소유자가 해당 계정이고 타 사용자 쓰기 권한이 없는 경우
#                        취약 = 그 외
# 전 Unix 계열 공통 로직: 로그인 가능한 계정 기준으로 검사.
# 주의(실기 테스트로 발견한 버그): $7(쉘)이 "nologin"/"false"로 끝나지 않는다고 해서 실사용
# 로그인 계정인 것은 아니다 — sync/shutdown/halt 등은 관례적으로 쉘 필드에 /bin/sync,
# /sbin/shutdown 같은 "실행 유틸리티"를 넣고 홈 디렉터리도 /sbin 처럼 여러 계정이 공유하는
# 시스템 디렉터리로 지정한다. 이런 공유 시스템 디렉터리를 "개인 홈"으로 취급해 소유자를
# 특정 계정으로 바꾸려 하면 실제 시스템 디렉터리(예: /usr/sbin)의 소유자를 망가뜨릴 위험이
# 있다. 홈이 공유 시스템 디렉터리인 계정은 애초에 대상에서 제외한다.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    accounts=$(awk -F: '
        $7 !~ /(nologin|false)$/ {
            home = $6
            if (home == "/sbin" || home == "/usr/sbin" || home == "/bin" || \
                home == "/usr/bin" || home == "/" || home == "") next
            print $1":"home
        }
    ' "$passwd_file")
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
