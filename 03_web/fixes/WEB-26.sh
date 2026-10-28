# WEB-26 (중) 로그 디렉터리 및 파일 권한 설정 — 조치 [fix: auto]
# checks/WEB-26.sh 와 같은 기준(lib/common.sh web_log_dirs 의 로그 폴더, 기타 권한 비트 하나라도)으로 찾은
# 로그 폴더·파일에서 기타(other) 권한만 제거한다(가이드 조치 "chmod o-rwx"). 소유자·그룹 권한은 그대로라
# 로그를 쓰는 웹 서버(root 마스터 또는 소유 계정)와 adm 그룹 등의 읽기에는 영향이 없다.
run_fix() {
    detect_web_engines
    applied=""

    fix_log_dirs() {
        for _dir in $(web_log_dirs "$1"); do
            [ -d "$_dir" ] || continue
            _dp=$(stat -L -c '%a' "$_dir" 2>/dev/null)
            _touched=""
            if [ -n "$_dp" ] && perm_exceeds "$_dp" 7770; then
                fix_backup "$_dir"
                chmod o-rwx "$_dir" 2>/dev/null
                _touched=1
            fi
            _bad=$(find "$_dir/" -maxdepth 1 -type f \( -perm -0001 -o -perm -0002 -o -perm -0004 \) 2>/dev/null)
            # 파이프(| while)는 서브셸이라 fix_backup 실패 시의 중단(exit)이 전달되지 않으므로 here-doc 사용
            while IFS= read -r _f; do
                [ -z "$_f" ] && continue
                fix_backup "$_f"
                chmod o-rwx "$_f" 2>/dev/null
                _touched=1
            done <<EOF
$_bad
EOF
            [ -n "$_touched" ] && applied="$applied $_dir"
        done
    }

    case " $WEB_ENGINES " in *" apache "*) fix_log_dirs apache ;; esac
    case " $WEB_ENGINES " in *" nginx "*) fix_log_dirs nginx ;; esac
    case " $WEB_ENGINES " in *" tomcat "*) fix_log_dirs tomcat ;; esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="로그 폴더/파일의 일반 사용자(other) 접근 권한을 제거함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="일반 사용자 접근 권한이 있는 로그 폴더/파일이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
