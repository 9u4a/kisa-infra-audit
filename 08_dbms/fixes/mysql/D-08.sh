# D-08 (상) 안전한 암호화 알고리즘 사용 [MySQL] — 조치 [fix: confirm]
# 원복: 불가 — 원래 비밀번호·인증 플러그인으로 되돌릴 수 없음
# checks/mysql/D-08.sh: 취약 = mysql_native_password(SHA-1)를 쓰는 계정 존재. 해당 계정을
# caching_sha2_password(SHA-256)로 전환한다 - 기존 해시를 재사용할 수 없어 비밀번호를 새로 설정해야 한다.
# 1.3.0: 무작위 비밀번호 생성을 폐지했다 - 애플리케이션 계정까지 아무도 모르는 값으로 바뀌어 서비스가
# 즉시 끊겼다. 계정마다 사전 승인 + 운영자 직접 입력(lib/common.sh fix_read_new_password), 비대화형이면
# 바꾸지 않는다. 도구가 접속에 쓰는 계정은 맨 마지막에 바꾼다(먼저 바꾸면 이후 조치·원복이 접속 실패).
# 원복 불가(원래 비밀번호를 알 수 없음) - 계정별 승인 문구에 명시한다.
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    out=$(mysql_query "SELECT user, host FROM mysql.user WHERE plugin IN ('mysql_native_password','mysql_old_password');")
    if [ -z "$out" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="SHA-1 기반 플러그인을 쓰는 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi
    if ! fix_tty_available; then
        FIX_STATUS="ERROR"; FIX_DETAIL="계정별 승인과 새 비밀번호 입력이 필요해 비대화형 실행에서는 변경하지 않음(대상: $(printf '%s' "$out" | awk '{printf "%s@%s ", $1, $2}'))"; FIX_EVIDENCE=""
        return
    fi

    self_user=${DB_USER:-root}
    ordered=$(printf '%s\n' "$out" | awk -v s="$self_user" '$1 != s' ; printf '%s\n' "$out" | awk -v s="$self_user" '$1 == s')

    fix_db_queue_rollback "mysql" "-- D-08: 계정을 caching_sha2_password 로 전환하며 비밀번호를 재설정함(원복 SQL 없음 - 원래 비밀번호를 알 수 없음)"

    applied=""; skipped=""; failed=""
    old_ifs=$IFS; IFS='
'
    for line in $ordered; do
        IFS=$old_ifs
        [ -z "$line" ] && { IFS='
'; continue; }
        user=$(printf '%s' "$line" | awk '{print $1}')
        host=$(printf '%s' "$line" | awk '{print $2}')
        note=""
        [ "$user" = "$self_user" ] && note=" [주의: 이 도구가 지금 접속에 쓰는 계정 - 바꾼 뒤에는 새 비밀번호로 DB_PASSWORD 를 다시 지정해야 함]"
        if fix_confirm_tty "  $user@$host 를 SHA-256(caching_sha2_password)으로 전환하려면 새 비밀번호가 필요합니다. 이 계정을 쓰는 애플리케이션 설정도 함께 바꿔야 하며 원래 비밀번호로 되돌릴 수 없습니다.$note 진행할까요?" \
           && fix_read_new_password "$user@$host"; then
            q_pw=$(sql_quote_mysql "$FIX_NEW_PASSWORD"); FIX_NEW_PASSWORD=""
            q_u=$(sql_quote_mysql "$user"); q_h=$(sql_quote_mysql "$host")
            if db_exec_stdin mysql "ALTER USER '$q_u'@'$q_h' IDENTIFIED WITH caching_sha2_password BY '$q_pw';" >/dev/null; then
                applied="$applied $user@$host"
            else
                failed="$failed $user@$host($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
            fi
            q_pw=""
        else
            skipped="$skipped $user@$host"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="SHA-256(caching_sha2_password)으로 전환하고 운영자 입력 비밀번호로 재설정함:$applied${skipped:+ / 건너뜀:$skipped}${failed:+ / 실패:$failed} (비밀번호는 기록하지 않음)"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="변경하지 않음${skipped:+ - 건너뜀:$skipped}${failed:+ - 실패:$failed}"
    fi
    FIX_EVIDENCE=""
}
