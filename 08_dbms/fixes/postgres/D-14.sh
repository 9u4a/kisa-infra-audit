# D-14 (중) 데이터베이스의 주요 설정 파일 접근 권한 적절성 [PostgreSQL] — 조치 [fix: auto]
run_fix() {
    conf=$(postgres_config_path)
    hba=$(postgres_hba_path)
    if [ -z "$conf" ] && [ -z "$hba" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="postgresql.conf/pg_hba.conf 를 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    applied=""
    for f in "$conf" "$hba"; do
        [ -z "$f" ] && continue
        [ -f "$f" ] || continue
        perm=$(stat -L -c '%a' "$f" 2>/dev/null)
        [ -n "$perm" ] && [ "$perm" -le 640 ] 2>/dev/null && continue
        owner=$(stat -L -c '%U' "$f" 2>/dev/null)
        case "$owner" in
            root|postgres) : ;;
            *) owner="postgres" ;;
        esac
        fix_set_owner_perm "$f" "$owner" 640
        applied="$applied $f"
    done

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="설정 파일 권한을 640으로 설정함:$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="이미 모든 설정 파일이 640 이하임(이미 정상)"
    fi
    FIX_EVIDENCE=""
}
