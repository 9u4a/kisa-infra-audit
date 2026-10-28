# D-11 (상) DBA 이외의 인가되지 않은 사용자가 시스템 테이블에 접근할 수 없도록 설정 [MySQL] — 조치 [fix: confirm]
# 원복 방식: 회수 직전 SHOW GRANTS 의 mysql 스키마 GRANT 문을 큐에 넣어 그대로 다시 실행한다(예전에는 원복 불가였다).
# checks/mysql/D-11.sh 와 같은 범위(root/mysql.% 외 계정, 권한 테이블 직접 조회)를 본다(조치 후속 F-R6 - 예전 조치는
# information_schema.schema_privileges 만 보고 DB 단위 권한만 회수해, 진단이 새로 잡는 전역·테이블 권한이 남아
# 재검증 VULN → 원복으로 끝났다).
#  - DB 단위(mysql.db 의 db = 'mysql')·테이블 단위(mysql.tables_priv 의 db = 'mysql') 권한: 회수한다(자동).
#  - 전역 권한(*.*)·와일드카드 DB 권한(`%`.* 등): 회수하면 mysql 외 모든(또는 패턴에 맞는) DB 접근까지 끊겨 업무가
#    중단될 수 있어 자동으로 회수하지 않고 "수동 조치 필요"로 보고한다(fix.sh 는 PARTIAL/MANUAL 을 원복하지 않음).
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    _excl="user <> 'root' AND user NOT LIKE 'mysql.%'"
    _gr="CONCAT(QUOTE(user), '@', QUOTE(host))"
    # 자동 회수 대상: "<grantee>\t<ON 대상>" (ON 대상은 mysql.* 또는 mysql.`테이블`)
    targets=$(mysql_query "SELECT $_gr, 'mysql.*' FROM mysql.db WHERE $_excl AND db = 'mysql'
UNION SELECT $_gr, CONCAT('mysql.\`', REPLACE(table_name, '\`', '\`\`'), '\`') FROM mysql.tables_priv WHERE $_excl AND db = 'mysql'
ORDER BY 1, 2;") || {
        FIX_STATUS="ERROR"; FIX_DETAIL="권한 테이블 조회 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    }
    # 수동 조치 대상: 전역 권한·와일드카드 DB 권한
    manual=$(mysql_query "SELECT CONCAT($_gr, ' (전역 권한 *.*)') FROM mysql.user WHERE $_excl AND (Select_priv='Y' OR Insert_priv='Y' OR Update_priv='Y' OR Delete_priv='Y' OR Drop_priv='Y' OR Alter_priv='Y' OR Create_priv='Y')
UNION SELECT CONCAT($_gr, ' (와일드카드 DB 권한: ', db, ')') FROM mysql.db WHERE $_excl AND db <> 'mysql' AND 'mysql' LIKE db
ORDER BY 1;") || {
        FIX_STATUS="ERROR"; FIX_DETAIL="권한 테이블 조회 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    }

    applied=""; failed=""; rb_lost=""
    done_grantees=""
    old_ifs=$IFS; IFS='
'
    for line in $targets; do
        IFS=$old_ifs
        grantee=$(printf '%s' "$line" | cut -f1)
        on=$(printf '%s' "$line" | cut -f2)
        [ -z "$grantee" ] && { IFS='
'; continue; }
        # 원복용: 회수 전에 이 계정의 mysql 스키마 GRANT 문(SHOW GRANTS 원문)을 큐에 넣는다. 같은 계정은 한 번만.
        case "$done_grantees" in
            *"|$grantee|"*) : ;;
            *)
                done_grantees="$done_grantees|$grantee|"
                grants=$(mysql_query "SHOW GRANTS FOR $grantee;" | grep ' ON `mysql`\.' | sed 's/$/;/')
                if [ -n "$grants" ]; then
                    fix_db_queue_rollback "mysql" "$grants"
                else
                    rb_lost="$rb_lost $grantee"
                    fix_db_queue_rollback "mysql" "-- D-11: $grantee 의 mysql 스키마 권한을 회수함(회수 전 SHOW GRANTS 를 읽지 못해 자동 재부여 불가)"
                fi ;;
        esac
        # "ALL PRIVILEGES, GRANT OPTION" 을 함께 쓰는 형태는 ON 절 없는 전역 문법뿐이다(ON 과 함께 쓰면 1064). GRANT OPTION 은
        # 따로 회수하되 갖고 있지 않으면 MySQL 이 오류(1141)를 내므로 그 결과는 보지 않는다 - 남았는지는 fix.sh 재검증이 확인한다.
        if mysql_query "REVOKE ALL PRIVILEGES ON $on FROM $grantee;" >/dev/null; then
            mysql_query "REVOKE GRANT OPTION ON $on FROM $grantee;" >/dev/null 2>&1
            applied="$applied $grantee:$on"
        else
            failed="$failed $grantee:$on($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    manual_txt=$(printf '%s' "$manual" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    FIX_EVIDENCE=""
    detail="${applied:+mysql 스키마 권한 회수:$applied}${rb_lost:+ (원복 정보 없음:$rb_lost)}"
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="${detail:+$detail / }회수 실패:$failed"
    elif [ -n "$manual" ]; then
        if [ -n "$applied" ]; then FIX_STATUS="PARTIAL"; else FIX_STATUS="MANUAL"; fi
        FIX_DETAIL="${detail:+$detail / }수동 조치 필요 - 회수하면 mysql 외 DB 접근까지 끊길 수 있어 자동으로 회수하지 않음: $manual_txt (필요한 DB 단위 권한으로 다시 부여한 뒤 전역/와일드카드 권한을 회수할 것)"
    elif [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="$detail"
    else
        FIX_STATUS="NA"; FIX_DETAIL="mysql 스키마에 대한 비인가 권한이 없음(이미 정상)"
    fi
}
