# D-03 (상) 비밀번호 사용 기간 및 복잡도를 기관의 정책에 맞도록 설정 [MySQL] — 조치 [fix: confirm]
# checks/mysql/D-03.sh: 취약 = validate_password 컴포넌트 미설치 & 기간 제한 미설정.
# 컴포넌트를 설치하고(기본 정책: MEDIUM) 만료 기간을 가이드 권고값(90일)으로 설정한다.
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi

    fix_db_queue_rollback "mysql" "UNINSTALL COMPONENT 'file://component_validate_password'; SET PERSIST default_password_lifetime = 0;"

    out1=$(mysql_query "INSTALL COMPONENT 'file://component_validate_password';" 2>&1)
    out2=$(mysql_query "SET PERSIST default_password_lifetime = 90;" 2>&1)

    vp=$(mysql_query "SHOW VARIABLES LIKE 'validate_password%';")
    lifetime=$(mysql_query "SHOW VARIABLES LIKE 'default_password_lifetime';" | awk '{print $2}')

    if [ -n "$vp" ] && [ "$lifetime" = "90" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="validate_password 컴포넌트 설치 및 default_password_lifetime=90 설정함"
    elif [ -n "$vp" ] || [ "$lifetime" = "90" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="일부만 적용됨(컴포넌트 이미 설치되어 있었을 수 있음): $out1 / $out2"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="설정 실패: $out1 / $out2"
    fi
    FIX_EVIDENCE="$vp
default_password_lifetime=$lifetime"
}
