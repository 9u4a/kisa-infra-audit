# D-14 (중) 데이터베이스의 주요 설정 파일 접근 권한 적절성 [Oracle] — 조치 [fix: auto]
run_fix() {
    home=$(oracle_home)
    if [ -z "$home" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="ORACLE_HOME 을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    applied=""
    for f in "$home/network/admin/listener.ora" "$home/network/admin/sqlnet.ora"; do
        [ -f "$f" ] || continue
        perm=$(stat -L -c '%a' "$f" 2>/dev/null)
        [ -n "$perm" ] && [ "$perm" -le 644 ] 2>/dev/null && continue
        owner=$(stat -L -c '%U' "$f" 2>/dev/null)
        case "$owner" in
            root|oracle) : ;;
            *) owner="oracle" ;;
        esac
        fix_set_owner_perm "$f" "$owner" 644
        applied="$applied $f"
    done

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="설정 파일 권한을 644로 설정함:$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="이미 모든 설정 파일 권한이 적절함(이미 정상)"
    fi
    FIX_EVIDENCE=""
}
