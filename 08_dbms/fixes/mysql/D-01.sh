# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [MySQL] — 조치 [fix: confirm]
# checks/mysql/D-01.sh: 취약 = root 계정 비밀번호가 비어있음.
# 1.3.0: 무작위 비밀번호 생성을 폐지했다(아무도 새 값을 몰라 관리 접속이 끊겼음). 계정(root@호스트)마다
# 사전 승인을 받고 운영자가 새 비밀번호를 터미널에서 직접 입력한다(lib/common.sh fix_read_new_password).
# 비대화형이면 바꾸지 않는다. 비밀번호는 SQL 을 표준입력으로 보내 ps 에 노출하지 않고, 증적·로그·백업에
# 남기지 않는다. 원복 불가(원래 값이 "빈 비밀번호"라 되돌리는 것 자체가 취약 상태로의 복귀).
run_fix() {
    if ! command -v mysql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="mysql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    hosts=$(mysql_query "SELECT host FROM mysql.user WHERE user='root' AND (authentication_string='' OR authentication_string IS NULL);")
    if [ -z "$hosts" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="비밀번호가 비어있는 root 계정이 없음(이미 정상)"; FIX_EVIDENCE=""
        return
    fi
    if ! fix_tty_available; then
        FIX_STATUS="ERROR"; FIX_DETAIL="비밀번호는 운영자가 터미널에서 직접 입력해야 함 - 비대화형 실행이라 변경하지 않음(대상 root@:$(printf '%s' "$hosts" | tr '\n' ' '))"; FIX_EVIDENCE=""
        return
    fi

    fix_db_queue_rollback "mysql" "-- D-01: root 비밀번호를 운영자 입력값으로 설정함(원복하지 않음 - 원래 값이 빈 비밀번호)"

    applied=""; skipped=""; failed=""
    old_ifs=$IFS; IFS='
'
    for h in $hosts; do
        IFS=$old_ifs
        [ -z "$h" ] && { IFS='
'; continue; }
        if fix_confirm_tty "  root@$h 의 비밀번호가 비어 있습니다. 지금 새 비밀번호를 설정할까요? (이 계정을 쓰는 프로그램 설정도 함께 바꿔야 함)" \
           && fix_read_new_password "root@$h"; then
            q_pw=$(sql_quote_mysql "$FIX_NEW_PASSWORD"); FIX_NEW_PASSWORD=""
            q_h=$(sql_quote_mysql "$h")
            if db_exec_stdin mysql "ALTER USER 'root'@'$q_h' IDENTIFIED BY '$q_pw';" >/dev/null; then
                applied="$applied root@$h"
            else
                failed="$failed root@$h($(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null))"
            fi
            q_pw=""
        else
            skipped="$skipped root@$h"
        fi
        IFS='
'
    done
    IFS=$old_ifs

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="운영자가 입력한 새 비밀번호로 설정함:$applied${skipped:+ / 건너뜀:$skipped}${failed:+ / 실패:$failed} (비밀번호는 기록하지 않음)"
    else
        FIX_STATUS="ERROR"
        FIX_DETAIL="변경하지 않음${skipped:+ - 건너뜀:$skipped}${failed:+ - 실패:$failed}"
    fi
    FIX_EVIDENCE=""
}
