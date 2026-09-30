# WEB-26 (중) 로그 디렉터리 및 파일 권한 설정 — 조치 [fix: auto]
# checks/WEB-26.sh 가 찾아낸 "other 읽기/쓰기 권한이 있는" 로그 파일에서 그 권한만 제거한다.
run_fix() {
    detect_web_engines
    applied=""

    fix_log_dir() {
        _dir=$1
        [ -d "$_dir" ] || return
        _bad=$(find "$_dir" -maxdepth 1 -type f -perm -0006 2>/dev/null)
        [ -z "$_bad" ] && return
        printf '%s\n' "$_bad" | while IFS= read -r _f; do
            [ -z "$_f" ] && continue
            fix_backup "$_f"
            chmod o-rwx "$_f" 2>/dev/null
        done
        applied="$applied $_dir"
    }

    case " $WEB_ENGINES " in *" apache "*)
        fix_log_dir "/usr/local/apache2/logs"
        fix_log_dir "/var/log/apache2"
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        fix_log_dir "/var/log/nginx"
    esac
    case " $WEB_ENGINES " in *" tomcat "*)
        home=$(tomcat_home)
        fix_log_dir "$home/logs"
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="로그 디렉터리 내 일반 사용자 접근 권한이 있던 파일의 권한을 제거함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="일반 사용자 접근 권한이 있는 로그 파일이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
