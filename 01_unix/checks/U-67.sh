# U-67 (중) 로그 디렉터리 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리 내 로그 파일의 소유자가 root이고 권한이 644 이하
#                        취약 = 소유자가 root가 아니거나 권한이 644를 초과하는 경우
# 자동화 범위: LINUX/SOLARIS 기준 /var/log, AIX 기준 /var/adm, HP-UX 기준 /var/adm/syslog
# (경로는 문서 기준이며 AIX/HP-UX 는 미검증).
# 디렉터리 최상위(하위 디렉터리 제외)만 본다 - find -maxdepth 는 GNU/BSD 확장이라 Solaris/AIX/
# HP-UX 의 네이티브 find 에서 지원 여부를 신뢰할 수 없으므로(실기 검증 불가), 셸 글롭으로
# 직접 순회한다(모든 Unix 셸에서 수십 년간 동일하게 동작하는 가장 안전한 공통 분모).

_u67_check_logdir() {
    _dir=$1
    if [ ! -d "$_dir" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$_dir 디렉터리를 찾을 수 없음"
        CHECK_EVIDENCE=""
        return
    fi
    _bad=""
    _n=0
    for _f in "$_dir"/*; do
        [ -f "$_f" ] || continue
        _n=$((_n + 1))
        [ "$_n" -gt 30 ] && break
        _ls=$(ls -ldL "$_f" 2>/dev/null)
        _owner=$(printf '%s' "$_ls" | awk '{print $3}')
        _perm=$(_mode_str_to_octal "$(printf '%s' "$_ls" | awk '{print $1}')")
        if [ -z "$_owner" ] || [ -z "$_perm" ]; then
            continue
        fi
        if [ "$_owner" != "root" ] || ! [ "$_perm" -le 644 ] 2>/dev/null; then
            _bad="$_bad
$_ls"
        fi
    done
    if [ -z "$_bad" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="$_dir 내 최상위 로그 파일이 모두 root 소유이며 권한이 644 이하임"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="$_dir 내 소유자가 root가 아니거나 권한이 644를 초과하는 로그 파일이 존재함 (최대 30건 확인)"
        CHECK_EVIDENCE=$(printf '%s' "$_bad" | sed '/^$/d')
    fi
}

run_check() {
    case "$OS_FAMILY" in
        rhel|debian|suse|solaris)
            _u67_check_logdir "/var/log"
            ;;
        aix)
            _u67_check_logdir "/var/adm"
            ;;
        hpux)
            _u67_check_logdir "/var/adm/syslog"
            ;;
        *)
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="환경(${OS_FAMILY})에 대한 자동 판정 로직 미구현"
            CHECK_EVIDENCE=""
            ;;
    esac
}
