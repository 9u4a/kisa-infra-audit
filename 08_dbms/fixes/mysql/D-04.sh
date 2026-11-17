# D-04 (상) 데이터베이스 관리자 권한을 꼭 필요한 계정 및 그룹에 대해서만 허용 [MySQL] — 조치 [fix: param]
# 값: accounts=관리자 권한을 회수할 계정(user@host, 쉼표 구분) - 진단 증적의 SUPER/GRANT/CREATE USER 보유 계정 중 불필요한 것
# 변경: 지정 계정이 가진 SUPER·CREATE USER·GRANT OPTION(전역 *.*)만 REVOKE - 그 밖의 권한은 그대로(원복 시 회수한 것만 다시 GRANT)
# 영향: 지정 계정으로 하던 계정 관리·권한 부여·서버 관리 작업(KILL·SET GLOBAL 등)이 즉시 실패
# 가이드 조치 방법: 관리자 권한을 꼭 필요한 계정에만. 필요 여부는 사람이 판단한다(진단 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): user@host 형식·mysql.user 에 있음·셋 중 하나 이상 보유·도구 접속 계정·root@localhost·
# MySQL 내부 계정이 아님·중복 없음.
run_fix() {
    vals=$(fix_param accounts)
    if [ -z "$vals" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 D-04.accounts 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    command -v mysql >/dev/null 2>&1 || { FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""; return; }
    errs=""; seen=" "; plan=""
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        case "$seen" in *" $a "*) errs="$errs / $a: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$a "
        u=${a%@*}; h=${a##*@}
        if [ "$u" = "$a" ] || ! printf '%s' "$u" | grep -qE '^[A-Za-z0-9_.$-]+$' || ! printf '%s' "$h" | grep -qE '^[A-Za-z0-9_.%:/-]+$'; then
            errs="$errs / $a: user@host 형식이 아님"; continue
        fi
        case "$u" in mysql.sys|mysql.session|mysql.infoschema) errs="$errs / $a: MySQL 내부 계정"; continue ;; esac
        [ "$u" = "root" ] && [ "$h" = "localhost" ] && { errs="$errs / $a: 기본 관리자(root@localhost)는 대상 아님"; continue; }
        [ "$u" = "${DB_USER:-root}" ] && { errs="$errs / $a: 도구가 접속에 쓰는 계정"; continue; }
        p=$(mysql_query "SELECT Super_priv, Create_user_priv, Grant_priv FROM mysql.user WHERE user='$u' AND host='$h';") || { errs="$errs / $a: 계정 조회 실패"; continue; }
        [ -n "$p" ] || { errs="$errs / $a: mysql.user 에 없는 계정"; continue; }
        set -- $p
        privs=""; [ "${1:-N}" = Y ] && privs="SUPER"; [ "${2:-N}" = Y ] && privs="${privs:+$privs, }CREATE USER"
        go=0; [ "${3:-N}" = Y ] && go=1
        [ -n "$privs" ] || [ "$go" -eq 1 ] || { errs="$errs / $a: SUPER/CREATE USER/GRANT OPTION 이 없음"; continue; }
        plan="$plan$a|$privs|$go
"
    done <<EOF
$vals
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    done_list=""; failed=""
    while IFS='|' read -r a privs go; do
        [ -n "$a" ] || continue
        u=${a%@*}; h=${a##*@}
        rb=""; sql=""
        [ -n "$privs" ] && { rb="GRANT $privs ON *.* TO '$u'@'$h';"; sql="REVOKE $privs ON *.* FROM '$u'@'$h';"; }
        [ "$go" -eq 1 ] && { rb="$rb GRANT USAGE ON *.* TO '$u'@'$h' WITH GRANT OPTION;"; sql="$sql REVOKE GRANT OPTION ON *.* FROM '$u'@'$h';"; }
        fix_db_queue_rollback mysql "$rb"
        left=$(mysql_query "$sql SELECT CONCAT(Super_priv, Create_user_priv, Grant_priv) FROM mysql.user WHERE user='$u' AND host='$h';" 2>/dev/null | tail -n 1)
        if [ "$left" = NNN ]; then done_list="$done_list $a"; else failed="$failed $a(남은 권한 $left)"; fi
    done <<EOF
$plan
EOF
    FIX_EVIDENCE=$(mysql_query "SELECT user, host FROM mysql.user WHERE Super_priv='Y' OR Grant_priv='Y' OR Create_user_priv='Y' ORDER BY user, host;" 2>/dev/null)
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="관리자 권한 회수 실패:$failed"
    else
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 계정의 SUPER·CREATE USER·GRANT OPTION 을 회수함:$done_list"
    fi
}
