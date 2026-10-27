# D-01 (상) 기본 계정의 비밀번호, 정책 등을 변경하여 사용 [PostgreSQL] — 조치 [fix: confirm]
# checks/postgres/D-01.sh: 취약 = postgres 계정 비밀번호가 NULL.
# 1.3.0: 무작위 비밀번호 생성을 폐지했다(아무도 새 값을 몰라 관리 접속이 끊겼음). 사전 승인 후 운영자가
# 새 비밀번호를 터미널에서 직접 입력한다(lib/common.sh fix_read_new_password). 비대화형이면 바꾸지 않는다.
# SQL 은 표준입력으로 보내 ps 에 노출하지 않고, 증적·로그·백업에 남기지 않는다. 원복하지 않는다
# (원래 값이 "비밀번호 없음"이라 되돌리는 것 자체가 취약 상태로의 복귀).
run_fix() {
    if ! command -v psql >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="psql 클라이언트가 없음"; FIX_EVIDENCE=""
        return
    fi
    if ! fix_tty_available; then
        FIX_STATUS="ERROR"; FIX_DETAIL="비밀번호는 운영자가 터미널에서 직접 입력해야 함 - 비대화형 실행이라 변경하지 않음"; FIX_EVIDENCE=""
        return
    fi
    if ! fix_confirm_tty "  postgres 계정에 비밀번호가 없습니다. 지금 새 비밀번호를 설정할까요? (이 계정을 쓰는 프로그램·.pgpass 설정도 함께 바꿔야 함)" \
       || ! fix_read_new_password "postgres"; then
        FIX_STATUS="ERROR"; FIX_DETAIL="운영자가 건너뛰어 변경하지 않음"; FIX_EVIDENCE=""
        return
    fi

    fix_db_queue_rollback "postgres" "-- D-01: postgres 비밀번호를 운영자 입력값으로 설정함(원복하지 않음 - 원래 값이 비밀번호 없음)"
    q_pw=$(sql_quote_pg "$FIX_NEW_PASSWORD"); FIX_NEW_PASSWORD=""
    # log_statement 가 ddl/mod/all 이면(D-26 조치가 mod 로 설정함) 이 문장이 비밀번호 평문째 서버 로그에
    # 남는다 - 이 트랜잭션에서만 문장 로깅을 끈다(SET LOCAL 은 superuser 필요, 실패하면 아무것도 바꾸지 않음).
    # 반드시 db_exec_stdin(표준입력)으로 보낼 것: psql 이 문장을 하나씩 따로 보내 SET LOCAL 이 ALTER USER 보다
    # 먼저 적용된다. psql -c 로 한 메시지에 묶어 보내면 서버가 받는 즉시 전체 문자열을 기록해 비밀번호가 로그에
    # 남는다(log_statement=all 대조 실험으로 확인: 표준입력 0건, -c 1건).
    if ! db_exec_stdin postgres "BEGIN; SET LOCAL log_statement = 'none'; SET LOCAL log_min_duration_statement = -1; ALTER USER postgres PASSWORD '$q_pw'; COMMIT;" >/dev/null; then
        q_pw=""
        FIX_STATUS="ERROR"; FIX_DETAIL="postgres 비밀번호 설정 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; FIX_EVIDENCE=""
        return
    fi
    q_pw=""
    FIX_STATUS="APPLIED"
    FIX_DETAIL="postgres 계정에 운영자가 입력한 새 비밀번호를 설정함(비밀번호는 기록하지 않음)"
    FIX_EVIDENCE=""
}
