# U-24 (상) 사용자, 시스템 환경변수 파일 소유자 및 권한 설정 — 조치
run_fix() {
    passwd_file="/etc/passwd"
    dotfiles=".profile .kshrc .cshrc .bashrc .bash_profile .login .exrc .netrc"
    accounts=$(awk -F: '
        $7 !~ /(nologin|false)$/ {
            home = $6
            if (home == "/sbin" || home == "/usr/sbin" || home == "/bin" || \
                home == "/usr/bin" || home == "/" || home == "") next
            print $1":"home
        }
    ' "$passwd_file")
    applied=""
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
            owner=$(stat -c '%U' "$f" 2>/dev/null)
            other_write=$(find "$f" -perm -0002 2>/dev/null)
            if [ "$owner" != "root" ] && [ "$owner" != "$name" ]; then
                fix_backup "$f"; chown "$name" "$f" 2>/dev/null
                applied="$applied $f(owner->$name)"
            fi
            if [ -n "$other_write" ]; then
                fix_backup "$f"; chmod o-w "$f" 2>/dev/null
                applied="$applied $f(other-write제거)"
            fi
        done
        IFS='
'
    done
    IFS=$old_ifs
    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 환경변수 파일이 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="환경변수 파일 소유자/권한 조치:$applied"; FIX_EVIDENCE="$applied"
    fi
}
