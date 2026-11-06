# D-14 (중) 데이터베이스의 주요 설정 파일 접근 권한 적절성 [MySQL] — 조치 [fix: auto]
# 변경: 진단과 같은 범위(서버가 읽는 설정 파일 전부 + debian.cnf, lib/common_db.sh mysql_config_files) 중 기준(소유자 root/mysql,
# 권한 640 이하)을 벗어난 파일만 권한 640, 소유자 root/mysql 이면 유지(그 외는 mysql 로 변경). 이미 640 보다 좁은 파일(600 등)은 그대로.
run_fix() {
    files=$(mysql_config_files)
    if [ -z "$files" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 설정 파일(my.cnf)을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    applied=""; failed=""; ev=""
    old_ifs=$IFS; IFS='
'
    for f in $files; do
        IFS=$old_ifs
        perm=$(stat -L -c '%a' "$f" 2>/dev/null)
        owner=$(stat -L -c '%U' "$f" 2>/dev/null)
        case "$owner" in
            root|mysql) _own_ok=1 ;;
            *) _own_ok=0; owner="mysql" ;;
        esac
        if [ -n "$perm" ] && perm_within "$perm" 640 && [ "$_own_ok" -eq 1 ]; then IFS='
'; continue; fi
        # 이미 640 보다 좁으면 권한은 그대로 두고 소유자만 바꾼다
        newperm=640
        [ -n "$perm" ] && perm_within "$perm" 640 && newperm=$perm
        if fix_set_owner_perm "$f" "$owner" "$newperm"; then
            applied="$applied $f"; ev="$ev
$FIX_EVIDENCE"
        else
            failed="$failed $f"
        fi
        IFS='
'
    done
    IFS=$old_ifs
    FIX_EVIDENCE="$ev"
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="${applied:+적용:$applied / }적용 실패:$failed"
    elif [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="설정 파일 소유자·권한을 기준(root/mysql, 640 이하)으로 설정함:$applied"
    else
        FIX_STATUS="NA"; FIX_DETAIL="이미 모든 설정 파일이 기준을 충족함(이미 정상)"
    fi
}
