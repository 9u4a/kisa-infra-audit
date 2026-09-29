# U-31 (중) 홈디렉토리 소유자 및 권한 설정 — 조치
# 주의: checks/U-31.sh 와 동일하게, /sbin 등 공유 시스템 디렉터리를 홈으로 쓰는 계정
# (sync/shutdown/halt 등)은 실제 시스템 디렉터리 소유자를 망가뜨릴 수 있어 제외한다
# (실기 테스트로 /usr/sbin chown 시도까지 이어지는 실제 버그를 발견).
run_fix() {
    passwd_file="/etc/passwd"
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
        owner=$(stat -c '%U' "$home" 2>/dev/null)
        other_write=$(find "$home" -maxdepth 0 -perm -0002 2>/dev/null)
        if [ "$owner" != "$name" ]; then
            fix_backup "$home"; chown "$name" "$home" 2>/dev/null
            applied="$applied $home(owner->$name)"
        fi
        if [ -n "$other_write" ]; then
            fix_backup "$home"; chmod o-w "$home" 2>/dev/null
            applied="$applied $home(other-write제거)"
        fi
        IFS='
'
    done
    IFS=$old_ifs
    if [ -z "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="조치가 필요한 홈 디렉토리가 없음"; FIX_EVIDENCE=""
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="홈 디렉토리 소유자/권한 조치:$applied"; FIX_EVIDENCE="$applied"
    fi
}
