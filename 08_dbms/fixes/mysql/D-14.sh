# D-14 (중) 데이터베이스의 주요 설정 파일 접근 권한 적절성 [MySQL] — 조치 [fix: auto]
# 변경: my.cnf 권한 640, 소유자 root/mysql 이면 유지(그 외는 mysql 로 변경)
run_fix() {
    f=$(mysql_config_path)
    if [ -z "$f" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 설정 파일(my.cnf)을 찾을 수 없음"; FIX_EVIDENCE=""
        return
    fi
    owner=$(stat -L -c '%U' "$f" 2>/dev/null)
    case "$owner" in
        root|mysql) : ;;
        *) owner="mysql" ;;
    esac
    fix_set_owner_perm "$f" "$owner" 640
}
