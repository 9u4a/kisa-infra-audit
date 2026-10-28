# D-08 (상) 안전한 암호화 알고리즘 사용 [PostgreSQL] — 조치 [fix: confirm]
# 원복: 일부 — password_encryption 은 되돌리지만, 다시 설정한 role 비밀번호는 원래 값으로 되돌릴 수 없음
# checks/postgres/D-08.sh: 취약 = password_encryption 이 md5, 또는 설정은 scram-sha-256 이나 pg_authid 에
# md5 해시로 저장된 role 이 남아 있음(진단 검수 D-R7).
# ① password_encryption 을 scram-sha-256 으로 바꾼다(GUC, 원복 SQL 큐).
# ② md5 로 저장된 role 은 해시를 변환할 방법이 없어 비밀번호를 다시 설정해야 scram 으로 저장된다(조치 후속 F-R6 -
#    예전 조치는 ①만 해서 재검증 VULN → 원복으로 끝났다). MySQL D-08 과 같이 role 마다 사전 승인 + 운영자 직접 입력
#    (fix_read_new_password)으로만 바꾸고, 비대화형이거나 건너뛴 role 은 "수동 조치 필요"(PARTIAL/MANUAL)로 정직하게
#    보고한다 - fix.sh 는 이 상태를 원복하지 않는다(①까지 되돌리면 안전한 설정을 잃는다).
#    도구가 접속에 쓰는 role 은 맨 마지막에 바꾼다(먼저 바꾸면 이후 조치·원복이 접속 실패).
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    before=$(psql_query "SHOW password_encryption;") || {
        FIX_STATUS="ERROR"; FIX_DETAIL="password_encryption 조회 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    }
    md5roles=$(psql_query "SELECT rolname FROM pg_authid WHERE rolpassword LIKE 'md5%' ORDER BY rolname;") || {
        FIX_STATUS="ERROR"; FIX_DETAIL="md5 로 저장된 role 조회 실패(pg_authid, superuser 필요): $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    }

    guc_done=""
    case "$before" in
        *scram-sha-256*) : ;;
        *)
            # 원복 큐는 역순으로 실행된다(ALTER SYSTEM → reload). 한 항목에 둘을 묶으면 psql -c 가 한 트랜잭션으로 보내
            # "ALTER SYSTEM cannot run inside a transaction block" 으로 원복이 실패한다(예전 큐가 그랬다).
            fix_db_queue_rollback "postgres" "SELECT pg_reload_conf();"
            fix_db_queue_rollback "postgres" "ALTER SYSTEM SET password_encryption = '$(sql_quote_pg "$before")';"
            psql_query "ALTER SYSTEM SET password_encryption = 'scram-sha-256';" >/dev/null 2>&1
            psql_query "SELECT pg_reload_conf();" >/dev/null 2>&1
            after=$(psql_query "SHOW password_encryption;")
            case "$after" in
                *scram-sha-256*) guc_done="password_encryption 을 scram-sha-256 으로 설정함(변경 전: $before)" ;;
                *)
                    FIX_STATUS="ERROR"; FIX_DETAIL="password_encryption 설정 실패(현재값: $after)"; FIX_EVIDENCE="password_encryption = $after"
                    return ;;
            esac ;;
    esac

    applied=""; left=""; failed=""
    if [ -n "$md5roles" ]; then
        self_user=${DB_USER:-postgres}
        ordered=$(printf '%s\n' "$md5roles" | awk -v s="$self_user" 'NF && $0 != s'; printf '%s\n' "$md5roles" | awk -v s="$self_user" '$0 == s')
        old_ifs=$IFS; IFS='
'
        for role in $ordered; do
            IFS=$old_ifs
            note=""
            [ "$role" = "$self_user" ] && note=" [주의: 이 도구가 지금 접속에 쓰는 role - 바꾼 뒤에는 새 비밀번호로 DB_PASSWORD 를 다시 지정해야 함]"
            if fix_tty_available \
               && fix_confirm_tty "  role $role 의 비밀번호가 md5 해시로 저장되어 있습니다. scram-sha-256 으로 다시 저장하려면 비밀번호를 새로 설정해야 합니다(이 role 을 쓰는 애플리케이션 설정도 함께 바꿔야 하며 원래 값으로 되돌릴 수 없음).$note 진행할까요?" \
               && fix_read_new_password "role $role"; then
                q_pw=$(sql_quote_pg "$FIX_NEW_PASSWORD"); FIX_NEW_PASSWORD=""
                q_role=$(printf '%s' "$role" | sed 's/"/""/g')
                # 비밀번호 평문이 서버 로그에 남지 않게 이 트랜잭션만 문장 로깅을 끈다(fixes/postgres/D-01.sh 와 같은 이유로 표준입력)
                if db_exec_stdin postgres "BEGIN; SET LOCAL log_statement = 'none'; SET LOCAL log_min_duration_statement = -1; SET LOCAL password_encryption = 'scram-sha-256'; ALTER ROLE \"$q_role\" PASSWORD '$q_pw'; COMMIT;" >/dev/null; then
                    # 원복 불가 기록은 실제로 바꾼 role 마다 남긴다(건너뛴 role 은 원복할 것이 없다)
                    fix_db_queue_rollback "postgres" "-- D-08: role $role 의 비밀번호를 운영자 입력값으로 다시 설정함(원복 SQL 없음 - 원래 비밀번호를 알 수 없음)"
                    applied="$applied $role"
                else
                    failed="$failed $role($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
                fi
                q_pw=""
            else
                left="$left $role"
            fi
            IFS='
'
        done
        IFS=$old_ifs
    fi

    FIX_EVIDENCE="password_encryption = $(psql_query "SHOW password_encryption;" 2>/dev/null)"
    detail="${guc_done}${applied:+${guc_done:+ / }md5 role 비밀번호 재설정(scram-sha-256):$applied (비밀번호는 기록하지 않음)}"
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="${detail:+$detail / }role 비밀번호 재설정 실패:$failed${left:+ / 미처리:$left}"
    elif [ -n "$left" ]; then
        if [ -n "$detail" ]; then FIX_STATUS="PARTIAL"; else FIX_STATUS="MANUAL"; fi
        FIX_DETAIL="${detail:+$detail / }수동 조치 필요 - 비밀번호가 md5 해시로 저장된 role:$left (해시를 변환할 수 없어 비밀번호를 다시 설정해야 함: psql 에서 \\password <role> 또는 ALTER ROLE <role> PASSWORD ...; 대화형 터미널에서 fix.sh 를 실행하면 role 마다 직접 입력 가능)"
    elif [ -n "$detail" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="$detail"
    else
        FIX_STATUS="NA"; FIX_DETAIL="password_encryption 이 이미 scram-sha-256 이고 md5 로 저장된 role 이 없음(이미 정상)"
    fi
}
