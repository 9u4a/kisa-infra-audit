# U-67 (중) 로그 디렉터리 소유자 및 권한 설정
# 판단 기준(가이드 원문): 양호 = 로그 디렉터리 내 로그 파일의 소유자가 root이고 권한이 644 이하
#                        취약 = 소유자가 root가 아니거나 권한이 644를 초과하는 경우
# 자동화 범위: LINUX/SOLARIS 기준 /var/log, AIX 기준 /var/adm, HP-UX 기준 /var/adm/syslog
# (경로는 문서 기준이며 AIX/HP-UX 는 미검증).
# 진단 검수 U-R11: 예전에는 디렉터리 최상위 30개 파일만 보고, 소유자·권한을 못 읽은 파일은 건너뛰었다.
# 이제 하위 디렉터리까지 모든 일반 파일을 POSIX find 조건(-maxdepth 없이 -user/-perm 만 - Solaris/AIX/HP-UX
# 네이티브 find 에도 있는 표준 조건)으로 검사하고, 시간 초과·find 실패는 "위반 없음"으로 보지 않는다(ERROR).
# 644 초과 = 0133 비트 또는 특수비트(4000/2000/1000) 중 하나라도 있음(-perm -0133 은 "전부"라 쓰지 않는다).
U67_FIND_COND='( ! -user root -o -perm -0100 -o -perm -0020 -o -perm -0010 -o -perm -0002 -o -perm -0001 -o -perm -4000 -o -perm -2000 -o -perm -1000 )'

_u67_check_logdir() {
    _dir=$1
    if [ ! -d "$_dir" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$_dir 디렉터리를 찾을 수 없음"
        CHECK_EVIDENCE=""
        return
    fi
    # shellcheck disable=SC2086
    _out=$( { set -f; run_to 300 find "$_dir" -type f $U67_FIND_COND -print 2>/dev/null; echo "__RC=$?"; } \
        | awk '/^__RC=/ { print "__N=" c + 0; print; exit } { c++; if (c <= 50) print }')
    _rc=$(printf '%s\n' "$_out" | sed -n 's/^__RC=//p')
    _cnt=$(printf '%s\n' "$_out" | sed -n 's/^__N=//p')
    _list=$(printf '%s\n' "$_out" | grep -vE '^__(RC|N)=' | sed '/^$/d')
    if [ -n "$_list" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="$_dir 내(하위 포함) 소유자가 root가 아니거나 권한이 644를 초과하는 로그 파일이 ${_cnt:-?}건 존재함 (최대 50건 표시)"
        CHECK_EVIDENCE=$(printf '%s\n' "$_list" | while IFS= read -r _f; do ls -ld "$_f" 2>/dev/null || printf '%s\n' "$_f"; done)
    elif [ -z "$_rc" ] || [ "$_rc" -ne 0 ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$_dir 검색(find)이 실패하거나 시간 제한(300초)을 넘김(종료코드 ${_rc:-?}) - 확인하지 못함"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="$_dir 내(하위 포함) 로그 파일이 모두 root 소유이며 권한이 644 이하임"
        CHECK_EVIDENCE=""
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
