# U-24 (상) 사용자, 시스템 환경변수 파일 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 환경변수 파일 소유자가 root 또는 해당 계정이고, root/소유자 외
#                        쓰기 권한이 없는 경우 / 취약 = 그 외
# 전 Unix 계열 공통 로직: 로그인 가능한 계정들의 홈 디렉터리 내 대표 환경변수 파일들을 검사.

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    dotfiles=".profile .kshrc .cshrc .bashrc .bash_profile .login .exrc .netrc"
    violations=""
    evidence=""
    checked=0

    accounts=$(awk -F: '$7 !~ /(nologin|false)$/ {print $1":"$6}' "$passwd_file")
    # 서브셸 while-read 로는 상위 변수(violations 등) 갱신이 안 되므로 for 루프 사용
    old_ifs=$IFS; IFS='
'
    for entry in $accounts; do
        IFS=$old_ifs
        name=${entry%%:*}
        home=${entry#*:}
        [ -d "$home" ] || continue
        for df in $dotfiles; do
            f="$home/$df"
            [ -e "$f" ] || continue
            checked=$((checked + 1))
            owner=$(stat -c '%U' "$f" 2>/dev/null)
            evidence="$evidence
$(ls -l "$f" 2>/dev/null)"
            if [ "$owner" != "root" ] && [ "$owner" != "$name" ]; then
                violations="$violations $f(owner=$owner)"
                continue
            fi
            perm_other_write=$(find "$f" -perm -0002 2>/dev/null)
            if [ -n "$perm_other_write" ]; then
                violations="$violations $f(other-write)"
            fi
        done
        IFS='
'
    done
    IFS=$old_ifs

    if [ "$checked" -eq 0 ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="검사 대상 환경변수 파일이 존재하지 않음"
        CHECK_EVIDENCE=""
    elif [ -z "$violations" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="검사한 환경변수 파일(${checked}개)이 모두 소유자 기준을 충족하고 타 사용자 쓰기 권한이 없음"
        CHECK_EVIDENCE="$evidence"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="소유자가 부적절하거나 타 사용자 쓰기 권한이 부여된 환경변수 파일이 존재함:$violations"
        CHECK_EVIDENCE="$evidence"
    fi
}
