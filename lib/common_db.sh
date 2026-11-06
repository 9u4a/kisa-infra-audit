# lib/common_db.sh — 08_dbms 엔진 탐지·운영 안전장치·원격 판별·권한 확인·MySQL/PostgreSQL/Oracle 접속,
#   DB 재기동·Oracle 정적 파라미터 복구, SQL 기반 원복 큐
# lib/common.sh 가 source 한다(직접 source 하지 말 것). 1.5.0 D3 에서 common.sh(2686줄)를 나눴다 - 함수는 모두
# common.sh 를 source 한 뒤 쓸 수 있고, 최상위 코드는 변수 할당뿐이라 파일 순서와 무관하다.
# shellcheck shell=sh

# ---- DBMS 공통: 엔진 탐지 (08_dbms) -----------------------------------------
# 로컬에서 구동 중인 DBMS 데몬을 /proc 기반으로 탐지한다 (ps/pgrep 미존재 이미지 대응,
# 03_web 에서 검증된 방식 재사용). 여러 엔진이 동시에 감지되면 DBMS_ENGINE 을 비워
# run.sh 가 -e 로 명시적으로 선택하도록 안내한다 (DBMS는 엔진별 카탈로그/권한 체계가
# 완전히 달라 Web처럼 여러 엔진을 한 번에 합산 진단하지 않는다).
detect_dbms_engine() {
    _found=""
    [ -n "$(proc_pids_by_comm mysqld)" ] && _found="$_found mysql"
    [ -n "$(proc_pids_by_comm postgres)" ] && _found="$_found postgres"
    _found=$(printf '%s' "$_found" | awk '{$1=$1};1')
    _count=$(printf '%s\n' "$_found" | wc -w | tr -d ' ')
    if [ "$_count" -eq 1 ]; then
        DBMS_ENGINE="$_found"
    else
        DBMS_ENGINE=""
        DBMS_ENGINES_FOUND="$_found"
    fi
}

# ---- DBMS 공통: 운영 안전장치 (무기한 대기·계정 잠금 방지) ------------------------
# 1) 모든 DB 클라이언트 호출은 _db_run 으로 감싸 DB_CMD_TIMEOUT 초 안에 끝나지 않으면 중단한다.
#    timeout 명령이 없는 환경에서는 그대로 실행한다(대상 무설치 원칙). timeout 이 감싼 자식은
#    TTY 를 읽을 수 없어 비밀번호 프롬프트로 멈추는 일도 함께 막힌다.
# 2) run.sh 가 db_preflight 로 접속을 딱 1번 시험해 실패하면 DB_CONN_FAILED=1 을 세운다. 이후
#    *_query 는 접속을 시도하지 않고 사유만 DB_ERR_FILE 에 남긴다 - 잘못된 비밀번호로 항목 수
#    (최대 18회)만큼 로그인을 반복해 Oracle FAILED_LOGIN_ATTEMPTS(기본 10회)·MSSQL CHECK_POLICY
#    등으로 운영 계정이 잠기는 것을 막는다.
# DB_CMD_TIMEOUT=0 이면 제한하지 않는다 - 인스턴스 재기동(SHUTDOWN/STARTUP)처럼 도중에 끊으면
# DB가 내려간 채로 남는 조치에서만 쓴다(fixes/oracle/D-19·D-26).
DB_CMD_TIMEOUT=${DB_CMD_TIMEOUT:-120}

_db_run() {
    if [ "$DB_CMD_TIMEOUT" != "0" ] && command -v timeout >/dev/null 2>&1; then
        timeout "$DB_CMD_TIMEOUT" "$@"
        _dbr_rc=$?
        [ "$_dbr_rc" -eq 124 ] && printf 'DB 명령이 %s초 안에 끝나지 않아 중단함(무기한 대기 방지)\n' "$DB_CMD_TIMEOUT" >&2
        return "$_dbr_rc"
    fi
    "$@"
}

_db_conn_blocked() {
    [ "${DB_CONN_FAILED:-0}" = "1" ] || return 1
    printf 'DB 접속 사전 점검 실패로 접속하지 않음(계정 잠금 방지): %s\n' "${DB_CONN_FAIL_MSG:-}" > "${DB_ERR_FILE:-/dev/null}"
    return 0
}

# Oracle 비밀번호 만료 "예고" 경고(실패 아님): 28002·28011(구버전), 28098(23ai 이상)
ORACLE_PW_WARN_RE='^ORA-(28002|28011|28098)'

# db_preflight  -- DBMS_ENGINE 에 맞춰 접속을 1회 시험. 실패 시 0이 아닌 값 반환 + DB_CONN_FAILED=1
db_preflight() {
    DB_CONN_FAILED=0; DB_CONN_FAIL_MSG=""
    case "${DBMS_ENGINE:-}" in
        mysql) _pf_out=$(mysql_query "SELECT 1;"); _pf_rc=$? ;;
        postgres) _pf_out=$(psql_query "SELECT 1;"); _pf_rc=$? ;;
        oracle)
            # 1단계: connect 한 줄만 보내고 표준입력을 바로 닫는다(진단 검수 D-R11). 비밀번호가 만료(ORA-28001)
            # 되면 sqlplus 가 "New password:" 를 표준입력에서 읽는데, 예전처럼 connect 뒤에 SET/SELECT 줄이 이어지면
            # 그 줄이 새 비밀번호로 읽힐 여지가 있었다. 여기서는 EOF 만 읽혀 비밀번호는 바뀌지 않는다. 접속 실패면
            # 이 1회로 끝나고(S3), 성공했을 때만 2단계 SELECT 로 넘어간다.
            _pf_out=$( { printf 'whenever sqlerror exit sql.sqlcode\n'
                         printf 'whenever oserror exit failure\n'
                         oracle_connect_line; } | _db_run sqlplus -s /nolog 2>"${DB_ERR_FILE:-/dev/null}" )
            _pf_rc=$?
            if printf '%s\n' "$_pf_out" | grep -qE 'ORA-28001|ORA-28000'; then
                _pf_rc=1
            elif [ "$_pf_rc" -eq 0 ] && printf '%s\n' "$_pf_out" | grep -vE "$ORACLE_PW_WARN_RE" | grep -qE '^(ORA-[0-9]+|SP2-[0-9]+)'; then
                _pf_rc=1
            fi
            if [ "$_pf_rc" -eq 0 ]; then
                _pf_out=$(oracle_query "SELECT 1 FROM dual;"); _pf_rc=$?
            fi
            ;;
        *) return 0 ;;
    esac
    if [ "$_pf_rc" -ne 0 ]; then
        DB_CONN_FAILED=1
        DB_CONN_FAIL_MSG=$( { head -n 1 "${DB_ERR_FILE:-/dev/null}"
                              printf '%s\n' "$_pf_out" | grep -E '^(ORA-|SP2-)' | head -n 1; } 2>/dev/null | tr '\n' ' ')
    fi
    export DB_CONN_FAILED DB_CONN_FAIL_MSG
    return "$_pf_rc"
}

# ---- DBMS 공통: 원격 모드 판별 (진단 검수 D-R1) ---------------------------------------
# --host 로 다른 서버에 접속하면 DB 조회는 원격 서버를 보지만, 설정 파일(my.cnf·pg_hba.conf·sqlnet.ora)·
# 프로세스(/proc)는 이 스크립트를 실행한 PC 의 것을 읽는다. 예전에는 분석자 PC(또는 클라이언트 컨테이너)의
# /etc/my.cnf 권한으로 D-14 를 VULN/GOOD 판정했다. 원격이면 해당 항목은 MANUAL 로 돌린다.
# db_is_remote  -- DB_HOST 가 비었거나 이 호스트 자신(이름·IP·루프백)이면 1(로컬), 아니면 0(원격)
db_is_remote() {
    _dr_h=${DB_HOST:-}
    _dr_h=${_dr_h#[}; _dr_h=${_dr_h%]}
    case "$_dr_h" in
        ""|localhost|localhost.localdomain|127.*|::1|0:0:0:0:0:0:0:1) return 1 ;;
    esac
    _dr_self=$( { hostname; hostname -f; hostname -s; hostname -I | tr ' ' '\n'
                  ip -o addr show | awk '{sub(/\/.*/, "", $4); print $4}'; } 2>/dev/null | awk 'NF')
    printf '%s\n' "$_dr_self" | grep -qixF -- "$_dr_h" && return 1
    # 이름이 이 호스트 IP 로 풀리면 로컬(예: --host db01.example.com 이 자기 자신). 조회는 5초 제한.
    for _dr_ip in $(run_to 5 getent hosts "$_dr_h" 2>/dev/null | awk '{print $1}'); do
        case "$_dr_ip" in 127.*|::1) return 1 ;; esac
        printf '%s\n' "$_dr_self" | grep -qixF -- "$_dr_ip" && return 1
    done
    return 0
}

# db_remote_skip <확인 대상 설명>  -- 원격 모드면 CHECK_* 를 MANUAL 로 채우고 0 반환(호출 check 는 return).
# DB_REMOTE 는 run.sh 가 한 번 계산해 export 하고, 없으면(fix.sh 재검증 등) 여기서 계산한다.
db_remote_skip() {
    if [ -z "${DB_REMOTE:-}" ]; then
        if db_is_remote; then DB_REMOTE=1; else DB_REMOTE=0; fi
    fi
    [ "$DB_REMOTE" = "1" ] || return 1
    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="원격 모드 - DB 서버 호스트에서 실행 필요: $1 은(는) DB 서버의 로컬 정보라 이 PC(--host ${DB_HOST:-})에서 확인할 수 없음"
    CHECK_EVIDENCE=""
    return 0
}

# ---- DBMS 공통: 접속 계정 권한 사전 확인 (진단 검수 D-R2/D-R5) ------------------------------
# 관리자가 아닌 계정은 카탈로그에서 자기 행만 보거나(information_schema·role_table_grants) 설정 경로
# 조회(SHOW hba_file)를 거부당해, "없음"을 GOOD 으로 읽는 거짓 양호가 났다. preflight 성공 뒤 1회 확인해
# DB_PRIV_LIMITED(항목 코드 목록)·DB_PRIV_MSG·DB_PRIV_STATUS 를 세운다 - run.sh 가 이 항목들의 판정을
# DB_PRIV_STATUS(기본 ERROR)로 바꾼다. 확인 쿼리 자체가 실패해도 "권한 부족"으로 본다(MSSQL 과 동일).
db_privilege_check() {
    DB_PRIV_LIMITED=""; DB_PRIV_MSG=""; DB_PRIV_STATUS="ERROR"
    [ "${DB_CONN_FAILED:-0}" = "1" ] && return 0
    case "${DBMS_ENGINE:-}" in
        mysql)
            if ! mysql_query "SELECT 1 FROM mysql.user LIMIT 1;" >/dev/null 2>&1; then
                DB_PRIV_LIMITED="D-01 D-02 D-04 D-06 D-08 D-10 D-11 D-21"
                DB_PRIV_MSG="접속 계정이 mysql.user 를 읽을 수 없음(관리자 권한 아님)"
            fi ;;
        postgres)
            _pc=$(psql_query "SELECT rolsuper::text || '|' || pg_has_role(current_user, 'pg_read_all_settings', 'USAGE')::text FROM pg_roles WHERE rolname = current_user;" 2>/dev/null | tr -d ' \t\r')
            case "$_pc" in
                true\|*) : ;;
                false\|true)
                    DB_PRIV_LIMITED="D-01 D-08 D-11"
                    DB_PRIV_MSG="접속 계정이 superuser 가 아님(pg_shadow·pg_authid 미조회, role_table_grants 는 자기 관련 행만 보임)" ;;
                *)
                    DB_PRIV_LIMITED="D-01 D-03 D-08 D-10 D-11 D-14"
                    DB_PRIV_MSG="접속 계정이 superuser·pg_read_all_settings 가 아님(설정 경로·일부 설정값·권한 카탈로그 미조회)" ;;
            esac ;;
        oracle)
            # CDB$ROOT 로 접속하면 dba_* 뷰가 루트 컨테이너만 보여 PDB 의 계정·객체가 빠진다(진단 검수 D-R5).
            _con=$(oracle_query "SELECT sys_context('USERENV','CON_NAME') FROM dual;" 2>/dev/null | tr -d ' \t\r' | awk 'NF' | head -n 1)
            if [ "$_con" = "CDB\$ROOT" ]; then
                _npdb=$(oracle_query "SELECT COUNT(*) FROM v\$pdbs WHERE name <> 'PDB\$SEED';" 2>/dev/null | tr -d ' \t\r' | awk 'NF' | head -n 1)
                if [ -n "$_npdb" ] && [ "$_npdb" != "0" ]; then
                    DB_PRIV_LIMITED="D-01 D-02 D-03 D-04 D-05 D-06 D-09 D-11 D-17 D-18 D-20 D-21"
                    DB_PRIV_MSG="CDB\$ROOT 에 접속함 - PDB(${_npdb}개)의 계정·객체는 조회되지 않음. PDB 서비스명(--db)으로 각각 다시 진단 필요"
                    DB_PRIV_STATUS="MANUAL"
                fi
            fi ;;
    esac
    export DB_PRIV_LIMITED DB_PRIV_MSG DB_PRIV_STATUS
}

# db_privilege_apply <code>  -- run.sh 루프에서 check 직후 호출. DB_PRIV_LIMITED 에 든 항목의 GOOD/VULN/MANUAL 을
# DB_PRIV_STATUS 로 바꾸고 원래 판정은 detail 에 남긴다. CDB$ROOT(DB_PRIV_STATUS=MANUAL)는 루트에서 찾은 취약은
# 그 자체로 사실이므로 GOOD 만 바꾼다(Oracle 실기: 루트의 OPEN 기본 계정 VULN 을 MANUAL 로 덮던 문제).
db_privilege_apply() {
    [ -n "${DB_PRIV_LIMITED:-}" ] || return 0
    case " $DB_PRIV_LIMITED " in *" $1 "*) ;; *) return 0 ;; esac
    case "$CHECK_STATUS" in
        GOOD|VULN|MANUAL)
            [ "$DB_PRIV_STATUS" = "MANUAL" ] && [ "$CHECK_STATUS" != "GOOD" ] && return 0
            CHECK_DETAIL="$DB_PRIV_MSG - 전체 정보를 보지 못해 판정 불가(일부만 보고 내린 판정: $CHECK_STATUS - $CHECK_DETAIL)"
            CHECK_STATUS="$DB_PRIV_STATUS" ;;
    esac
}

# ---- DBMS 공통: MySQL 연결/쿼리 ---------------------------------------------
# 접속 정보는 run.sh 가 파싱한 DB_HOST/DB_PORT/DB_USER/DB_SOCKET 환경변수를 사용하고,
# 비밀번호는 절대 인자로 노출하지 않고 MYSQL_PWD 환경변수로만 전달한다
# (비밀번호를 CLI 인자로 노출하지 않음). DB_ERR_FILE 은 run.sh 가 mktemp 로 준비한다.
mysql_args() {
    _a="-N -B --connect-timeout=5"
    [ -n "${DB_HOST:-}" ] && _a="$_a -h $DB_HOST"
    [ -n "${DB_PORT:-}" ] && _a="$_a -P $DB_PORT"
    [ -n "${DB_USER:-}" ] && _a="$_a -u $DB_USER"
    [ -n "${DB_SOCKET:-}" ] && _a="$_a -S $DB_SOCKET"
    printf '%s' "$_a"
}

# mysql_query <sql>  -- 결과를 탭 구분으로 stdout 에 출력, 실패 시 0이 아닌 값 반환
mysql_query() {
    _db_conn_blocked && return 1
    (
        [ -n "${DB_PASSWORD:-}" ] && export MYSQL_PWD="$DB_PASSWORD"
        # shellcheck disable=SC2046
        _db_run mysql $(mysql_args) -e "$1"
    ) 2>"${DB_ERR_FILE:-/dev/null}"
}

mysql_config_path() {
    for _f in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf \
              /etc/mysql/mariadb.conf.d/50-server.cnf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

# ---- DBMS 공통: PostgreSQL 연결/쿼리 ----------------------------------------
# -w: 비밀번호가 필요해도 프롬프트를 띄우지 않고 즉시 실패(대화형 대기 방지).
psql_args() {
    _a="-X -q -t -A -w --no-psqlrc"
    [ -n "${DB_HOST:-}" ] && _a="$_a -h $DB_HOST"
    [ -n "${DB_PORT:-}" ] && _a="$_a -p $DB_PORT"
    [ -n "${DB_USER:-}" ] && _a="$_a -U $DB_USER"
    _a="$_a -d ${DB_NAME:-postgres}"
    printf '%s' "$_a"
}

# psql_query <sql>  -- 결과를 |로 구분된 행으로 stdout 에 출력, 실패 시 0이 아닌 값 반환
# 쿼리 시간 제한은 PGOPTIONS(statement_timeout) 대신 _db_run 으로 건다 - pgbouncer 경유
# 접속은 options 시작 파라미터를 거부해 접속 자체가 실패할 수 있기 때문.
psql_query() {
    _db_conn_blocked && return 1
    (
        [ -n "${DB_PASSWORD:-}" ] && export PGPASSWORD="$DB_PASSWORD"
        export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
        # shellcheck disable=SC2046
        _db_run psql $(psql_args) -c "$1"
    ) 2>"${DB_ERR_FILE:-/dev/null}"
}

postgres_config_path() {
    _cf=$(psql_query "SHOW config_file;" 2>/dev/null | tr -d '\r' | awk '{$1=$1};1')
    if [ -n "$_cf" ] && [ -f "$_cf" ]; then printf '%s' "$_cf"; return; fi
    for _f in /var/lib/postgresql/data/postgresql.conf /var/lib/pgsql/data/postgresql.conf \
              /etc/postgresql/*/main/postgresql.conf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

postgres_hba_path() {
    _hf=$(psql_query "SHOW hba_file;" 2>/dev/null | tr -d '\r' | awk '{$1=$1};1')
    if [ -n "$_hf" ] && [ -f "$_hf" ]; then printf '%s' "$_hf"; return; fi
    for _f in /var/lib/postgresql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf \
              /etc/postgresql/*/main/pg_hba.conf; do
        [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

# postgres_other_dbs_manual  -- 접속한 DB 하나만 보고 GOOD 을 낸 check 가 호출한다. 접속 가능한 다른 DB 가
# 있으면 CHECK_STATUS 를 MANUAL 로 바꾸고 그 목록을 남긴다(진단 검수 D-R7, D-11/D-20). 다른 DB 에 추가로
# 접속하지 않는 이유: pg_hba 가 DB 별로 달라 접속 실패(로그인 실패 기록)가 늘 수 있다(S3).
postgres_other_dbs_manual() {
    _odb=$(psql_query "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate AND datname <> current_database() ORDER BY datname;" 2>/dev/null)
    _odb_rc=$?
    if [ "$_odb_rc" -ne 0 ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="다른 데이터베이스 목록을 조회하지 못함 - 접속 DB 판정: $CHECK_DETAIL"
    elif [ -n "$_odb" ]; then
        CHECK_STATUS="MANUAL"
        CHECK_DETAIL="접속한 DB(${DB_NAME:-postgres})에서는 양호: $CHECK_DETAIL - 다른 DB($(printf '%s' "$_odb" | tr '\n' ' '))는 확인하지 않음, --db 로 각각 진단 필요"
    fi
}

# ---- DBMS 공통: Oracle 연결/쿼리 --------------------------------------------
# 비밀번호는 sqlplus 인자(argv)로 절대 넘기지 않고, 접속 문자열을 표준입력(파이프)으로만
# 전달한다(ps 목록 노출 방지). DB_USER/DB_PASSWORD 미지정 시 OS 인증("/ as sysdba")으로 접속한다.
oracle_connect_line() {
    if [ -n "${DB_USER:-}" ] && [ -n "${DB_PASSWORD:-}" ]; then
        _target=""
        [ -n "${DB_HOST:-}" ] && _target="@//${DB_HOST}:${DB_PORT:-1521}/${DB_NAME:-FREE}"
        printf 'connect %s/%s%s\n' "$DB_USER" "$DB_PASSWORD" "$_target"
    else
        printf 'connect / as sysdba\n'
    fi
}

# oracle_query <sql>  -- 결과를 stdout 에 출력, 실패 시(SQL 오류/접속 실패) 0이 아닌 값 반환
# whenever 는 반드시 connect 보다 먼저 선언한다 - 뒤에 두면 접속 실패(ORA-01017 등)에 적용되지
# 않아 이후 SELECT 가 SP2-0640(Not connected)과 함께 rc=0 으로 끝나고, 오류 문구가 "결과 있음"으로
# 읽혀 거짓 VULN 이 난다. 같은 이유로 출력에 ORA-/SP2- 행이 있으면 실패로 본다.
oracle_query() {
    _db_conn_blocked && return 1
    _out=$(
        { printf 'whenever sqlerror exit sql.sqlcode\n'
          printf 'whenever oserror exit failure\n'
          oracle_connect_line
          # tab off: sqlplus 기본값(SET TAB ON)은 열 패딩 공백을 TAB 으로 바꿔 출력한다. 조치가 "|" 로 나눈 열에서 공백만
          # 지우던 탓에 "SYS<TAB>.DBA_USERS" 같은 이름으로 REVOKE 가 실패했다(1.4.0 D-C7, fixes/oracle/D-11·D-17 실기).
          printf 'set heading off feedback off pagesize 0 verify off linesize 500 trimspool on tab off\n'
          printf 'set colsep |\n'
          printf '%s\n' "$1"
          printf 'exit\n'
        } | _db_run sqlplus -s /nolog 2>"${DB_ERR_FILE:-/dev/null}"
    )
    _rc=$?
    # ORA-28002/28011(구버전)·ORA-28098(23ai 이상)은 비밀번호 만료 예고로, 접속 성공 시 함께 찍히는 경고다 - 예전에는
    # 이 줄 때문에 전 항목이 ERROR 가 됐다(진단 검수 D-R11). 경고 블록("ERROR:" 머리줄, 이어지는 설명 줄, Help 링크)만
    # 지우고 판정한다 - 남기면 "결과 있음=취약" check 가 거짓 VULN 을 낸다. ORA-28001(만료)은 db_preflight 1단계에서 걸러진다.
    if printf '%s\n' "$_out" | grep -qE "$ORACLE_PW_WARN_RE"; then
        _out=$(printf '%s\n' "$_out" | grep -vE "$ORACLE_PW_WARN_RE"'|^ERROR:[[:space:]]*$|password will expire|^Help: https?://docs\.oracle\.com/error-help/db/ora-280(02|11|98)' | sed '/^[[:space:]]*$/d')
    fi
    if [ "$_rc" -eq 0 ] && printf '%s\n' "$_out" | grep -qE '^(ORA-[0-9]+|SP2-[0-9]+)'; then
        _rc=1
    fi
    printf '%s\n' "$_out"
    return $_rc
}

# oracle_profile_limits <'RES1','RES2'>  -- "프로파일|자원|실효값" 행 출력. DEFAULT 프로파일과, 잠기지 않은(OPEN)
# 계정이 쓰는 모든 프로파일을 대상으로 하고, 사용자 정의 프로파일의 LIMIT 'DEFAULT' 는 DEFAULT 프로파일 값으로
# 풀어 쓴다. 예전에는 DEFAULT 프로파일만 봐서 실제 계정에 붙은 사용자 정의 프로파일이 UNLIMITED 여도 양호였다
# (진단 검수 D-R5, D-03/05/09).
oracle_profile_limits() {
    oracle_query "SELECT p.profile || '|' || p.resource_name || '|' || CASE WHEN p.limit = 'DEFAULT' THEN d.limit ELSE p.limit END FROM dba_profiles p JOIN dba_profiles d ON d.profile = 'DEFAULT' AND d.resource_name = p.resource_name WHERE p.resource_name IN ($1) AND (p.profile = 'DEFAULT' OR p.profile IN (SELECT profile FROM dba_users WHERE account_status = 'OPEN')) ORDER BY p.profile, p.resource_name;"
}

# oracle_profiles_unrestricted <'RES1','RES2'>  -- oracle_profile_limits 대상 프로파일 중, 주어진 자원의 실효값이
# 모두 미설정(UNLIMITED/NULL/빈 값)인 프로파일 이름을 공백으로 구분해 출력한다(checks/oracle/D-03·05·09 의 취약 판정과
# 같은 기준). 조회 실패 시 0이 아닌 값.
oracle_profiles_unrestricted() {
    _opu=$(oracle_profile_limits "$1") || return 1
    printf '%s\n' "$_opu" | awk -F'|' '
        NF >= 3 { p=$1; v=$3; gsub(/[ \t\r]/, "", p); gsub(/[ \t\r]/, "", v)
                  if (!(p in seen)) { seen[p]=1; order[++n]=p }
                  if (v != "" && v != "UNLIMITED" && v != "NULL") ok[p]=1 }
        END { for (i = 1; i <= n; i++) if (!(order[i] in ok)) printf "%s ", order[i] }'
}

# oracle_fix_profile_limits <'RES1','RES2'> <LIMIT 절>  -- 조치(fixes/oracle/D-03·05·09) 공통. 진단과 같은 범위(DEFAULT +
# OPEN 계정이 쓰는 사용자 정의 프로파일)에서 미설정 프로파일마다 ALTER PROFILE ... LIMIT <LIMIT 절> 을 적용한다(조치 후속
# F-R6 - 예전 조치는 DEFAULT 만 바꿔 사용자 정의 프로파일이 남아 재검증 VULN → 원복으로 끝났다). DEFAULT 를 먼저 고치고
# 다시 조회해, 값을 'DEFAULT' 로 상속하던 사용자 정의 프로파일은 건드리지 않는다(상속 유지). 원복 SQL 은 프로파일마다
# 조치 직전의 원래 값(상속이면 DEFAULT 키워드 그대로)으로 큐에 넣는다. FIX_STATUS/FIX_DETAIL/FIX_EVIDENCE 를 채운다.
oracle_fix_profile_limits() {
    FIX_EVIDENCE=""
    _ofp_bad=$(oracle_profiles_unrestricted "$1") || {
        FIX_STATUS="ERROR"; FIX_DETAIL="프로파일 조회 실패: $(head -n1 "${DB_ERR_FILE:-/dev/null}" 2>/dev/null)"; return
    }
    if [ -z "$_ofp_bad" ]; then
        FIX_STATUS="NA"; FIX_DETAIL="미설정 프로파일이 없음(이미 정상)"; return
    fi
    _ofp_order=""
    for _ofp_p in $_ofp_bad; do
        if [ "$_ofp_p" = "DEFAULT" ]; then _ofp_order="DEFAULT $_ofp_order"; else _ofp_order="$_ofp_order $_ofp_p"; fi
    done
    _ofp_done=""
    for _ofp_p in $_ofp_order; do
        if [ "$_ofp_p" != "DEFAULT" ]; then
            # DEFAULT 를 고친 뒤 상속('DEFAULT')으로 해소된 프로파일은 건너뛴다
            _ofp_now=$(oracle_profiles_unrestricted "$1") || { FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }프로파일 재조회 실패"; return; }
            case " $_ofp_now " in *" $_ofp_p "*) ;; *) continue ;; esac
        fi
        case "$_ofp_p" in
            *\"*|*\'*) FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }처리할 수 없는 프로파일 이름: $_ofp_p"; return ;;
        esac
        if [ "$_ofp_p" = "DEFAULT" ]; then _ofp_id="DEFAULT"; else _ofp_id="\"$_ofp_p\""; fi
        _ofp_raw=$(oracle_query "SELECT resource_name || ' ' || limit FROM dba_profiles WHERE profile = '$_ofp_p' AND resource_name IN ($1) ORDER BY resource_name;") || {
            FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }$_ofp_p 현재 값 조회 실패"; return
        }
        _ofp_rb=$(printf '%s\n' "$_ofp_raw" | awk 'NF >= 2 { printf " %s %s", $1, $2 }')
        if [ -z "$_ofp_rb" ]; then
            FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }$_ofp_p 현재 값을 읽지 못해 원복할 수 없으므로 변경하지 않음"; return
        fi
        fix_db_queue_rollback "oracle" "ALTER PROFILE $_ofp_id LIMIT$_ofp_rb;"
        _ofp_out=$(oracle_query "ALTER PROFILE $_ofp_id LIMIT $2;" 2>&1) || {
            FIX_STATUS="ERROR"; FIX_DETAIL="${_ofp_done:+적용:$_ofp_done / }ALTER PROFILE $_ofp_p 실패: $_ofp_out"; FIX_EVIDENCE="$_ofp_out"; return
        }
        _ofp_done="$_ofp_done $_ofp_p(변경 전:$_ofp_rb)"
    done
    FIX_STATUS="APPLIED"
    FIX_DETAIL="프로파일에 $2 설정함:$_ofp_done"
}

# oracle_conf_active <file>  -- .ora 파일에서 # 주석을 지운 내용을 출력(진단 검수 D-R6: 주석 처리된 설정을
# 유효한 설정으로 읽어 거짓 GOOD 이 났다). 읽지 못하면 0이 아닌 값 반환.
oracle_conf_active() {
    [ -r "$1" ] || return 1
    sed 's/#.*$//' "$1"
}

oracle_home() {
    if [ -n "${ORACLE_HOME:-}" ] && [ -d "$ORACLE_HOME" ]; then printf '%s' "$ORACLE_HOME"; return; fi
    for _d in /opt/oracle/product/*/dbhome* /opt/oracle/product/*/db* \
              /u01/app/oracle/product/*/dbhome_1 /u01/app/oracle/product/*/db_1; do
        [ -d "$_d" ] && { printf '%s' "$_d"; return; }
    done
}

oracle_sqlnet_ora() {
    _h=$(oracle_home)
    [ -n "$_h" ] && [ -f "$_h/network/admin/sqlnet.ora" ] && { printf '%s' "$_h/network/admin/sqlnet.ora"; return; }
    for _f in "${TNS_ADMIN:-}/sqlnet.ora" /etc/oracle/sqlnet.ora; do
        [ -n "$_f" ] && [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

oracle_listener_ora() {
    _h=$(oracle_home)
    [ -n "$_h" ] && [ -f "$_h/network/admin/listener.ora" ] && { printf '%s' "$_h/network/admin/listener.ora"; return; }
    for _f in "${TNS_ADMIN:-}/listener.ora" /etc/oracle/listener.ora; do
        [ -n "$_f" ] && [ -f "$_f" ] && { printf '%s' "$_f"; return; }
    done
}

# ---- DB 재기동 조치 헬퍼 (운영 안전 기준 F2, 1.3.0) ----------------------------------------------
# 정적 파라미터 조치(mysql D-07, postgres D-03/D-26)는 재기동이 필요하다. 예전에는 재기동 명령의 성공만 보고
# DB 가 실제로 떴는지 확인하지 않았고, 기동에 실패해도 설정을 되돌리지 않아 DB 가 내려간 채로 남을 수 있었다.

# db_wait_alive <초> — DBMS_ENGINE 에 접속될 때까지 최대 N초 기다린다(0=접속 확인, 1=시간 초과)
db_wait_alive() {
    _wa=0
    while [ "$_wa" -lt "$1" ]; do
        case "${DBMS_ENGINE:-}" in
            mysql) mysql_query "SELECT 1;" >/dev/null 2>&1 && return 0 ;;
            postgres) psql_query "SELECT 1;" >/dev/null 2>&1 && return 0 ;;
            oracle) oracle_query "SELECT 1 FROM dual;" >/dev/null 2>&1 && return 0 ;;
            *) return 1 ;;
        esac
        sleep 2; _wa=$((_wa + 2))
    done
    return 1
}

# db_restart_server — 지금 실행 중인 DB 서비스만 재기동한다. 0=재기동 명령 성공, 1=실패, 2=재기동 수단 없음
# (원격 실행 등). 예전처럼 실행 중이 아닌 유닛 이름까지 차례로 restart 하거나 systemd 밖에서 mysqld_safe 로
# 띄우지 않는다.
db_restart_server() {
    case "${DBMS_ENGINE:-}" in
        mysql) _units="mysqld mysql mariadb" ;;
        postgres) _units="postgresql postgresql-17 postgresql-16 postgresql-15 postgresql-14 postgresql-13 postgresql-12" ;;
        *) return 2 ;;
    esac
    if command -v systemctl >/dev/null 2>&1; then
        for _u in $_units; do
            systemctl is-active --quiet "$_u" 2>/dev/null || continue
            systemctl restart "$_u" 2>/dev/null && return 0
            return 1
        done
    fi
    if [ "$DBMS_ENGINE" = "postgres" ] && command -v pg_ctlcluster >/dev/null 2>&1; then
        _cl=$(pg_lsclusters 2>/dev/null | awk 'NR > 1 && $4 == "online" { print $1, $2; exit }')
        # shellcheck disable=SC2086
        [ -n "$_cl" ] && { pg_ctlcluster $_cl restart 2>/dev/null && return 0; return 1; }
    fi
    if command -v service >/dev/null 2>&1; then
        for _u in $_units; do
            service "$_u" status >/dev/null 2>&1 || continue
            service "$_u" restart >/dev/null 2>&1 && return 0
            return 1
        done
    fi
    return 2
}

# db_restart_or_revert <설명> — 재기동 후 기동을 확인하고, 뜨지 않으면 이 항목의 백업(설정 파일)으로 되돌린 뒤
# 다시 기동한다. 결과는 DB_RESTART_RESULT 에: ok / no_method / reverted / down(되돌렸는데도 안 뜸 - 즉시 수동 조치)
db_restart_or_revert() {
    db_restart_server
    case $? in
        2) DB_RESTART_RESULT="no_method"; return 1 ;;
    esac
    if db_wait_alive 60; then DB_RESTART_RESULT="ok"; return 0; fi
    log_error "[$FIX_CODE] $1 후 DB 가 다시 뜨지 않습니다 - 설정을 되돌리고 다시 기동합니다."
    fix_rollback_item "$FIX_CODE"
    db_restart_server
    if db_wait_alive 60; then DB_RESTART_RESULT="reverted"; else DB_RESTART_RESULT="down"; fi
    return 1
}

# ---- Oracle 정적 파라미터 조치의 재기동·복구 (D-19/D-26, 1.3.1) --------------------------------------
# SPFILE 을 바꾼 뒤 SHUTDOWN/STARTUP 을 하는데, 새 값 때문에 기동에 실패하면 인스턴스가 내려간 채로 남고 SQL 로는
# 되돌릴 수 없다(SPFILE 은 인스턴스가 떠 있어야 ALTER SYSTEM 으로 바꿀 수 있음). 그래서:
#   oracle_pfile_backup <코드>  — 변경 "전" SPFILE 을 PFILE 로 떠 둔다(실패하면 조치하지 말 것)
#   oracle_restart_or_recover   — 재기동 후 기동을 확인하고, 안 뜨면 PFILE 로 기동해 SPFILE 을 원래대로 다시
#                                 만들고 재기동한다. 결과는 DB_RESTART_RESULT(ok/reverted/down)
# PFILE 은 oracle 계정이 쓸 수 있는 $ORACLE_HOME/dbs 에 두고(백업 디렉터리는 root 700 이라 oracle 이 못 씀),
# 경로를 ORACLE_PFILE_BACKUP 에 담는다.
oracle_pfile_backup() {
    _oh=$(oracle_home)
    [ -n "$_oh" ] && [ -d "$_oh/dbs" ] || return 1
    ORACLE_PFILE_BACKUP="$_oh/dbs/kisa_${1}_$(date '+%Y%m%d%H%M%S').ora"
    oracle_query "CREATE PFILE='$ORACLE_PFILE_BACKUP' FROM SPFILE;" >/dev/null || return 1
    [ -s "$ORACLE_PFILE_BACKUP" ] || return 1
    # 백업 디렉터리에도 사본을 남긴다(원본 SPFILE 내용 증적)
    mkdir -p "$FIX_BACKUP_DIR/$FIX_CODE/_oracle" 2>/dev/null && cp -p "$ORACLE_PFILE_BACKUP" "$FIX_BACKUP_DIR/$FIX_CODE/_oracle/" 2>/dev/null
    return 0
}

oracle_restart_or_recover() {
    # 재기동은 도중에 끊으면 DB 가 내려간 채로 남으므로 시간 제한을 걸지 않는다
    DB_CMD_TIMEOUT=0 oracle_query "SHUTDOWN IMMEDIATE;
STARTUP;" >/dev/null 2>&1
    if db_wait_alive 120; then DB_RESTART_RESULT="ok"; return 0; fi
    log_error "[$FIX_CODE] 재기동 후 Oracle 이 열리지 않습니다 - 변경 전 PFILE 로 기동해 SPFILE 을 되돌립니다($ORACLE_PFILE_BACKUP)."
    DB_CMD_TIMEOUT=0 oracle_query "SHUTDOWN ABORT;" >/dev/null 2>&1
    DB_CMD_TIMEOUT=0 oracle_query "STARTUP PFILE='$ORACLE_PFILE_BACKUP';" >/dev/null 2>&1
    if db_wait_alive 120 \
       && DB_CMD_TIMEOUT=0 oracle_query "CREATE SPFILE FROM PFILE='$ORACLE_PFILE_BACKUP';" >/dev/null 2>&1; then
        # PFILE 로 떠 있는 상태 - 복원한 SPFILE 로 다시 기동해 이후 재기동에도 원래 값이 쓰이게 한다
        DB_CMD_TIMEOUT=0 oracle_query "SHUTDOWN IMMEDIATE;
STARTUP;" >/dev/null 2>&1
    fi
    if db_wait_alive 120; then DB_RESTART_RESULT="reverted"; else DB_RESTART_RESULT="down"; fi
    return 1
}

# ---- DBMS 전용: SQL 기반 원복 (08_dbms) -------------------------------------
# DB 상태는 파일이 아니라 SQL 실행 결과이므로, 파일 기반 fix_backup 과 달리 "원복용 SQL 문
# 자체"를 백업 위치에 기록해 두고 fix_rollback_item 이 그 SQL 을 다시 실행하는 방식으로
# 원복한다. fixes/<engine>/D-xx.sh 는 실제 변경 전에 반드시 이 함수로 원복 SQL 을 큐에 넣는다.
fix_db_queue_rollback() {
    _engine=$1; _sql=$2
    _dir="$FIX_BACKUP_DIR/$FIX_CODE/dbsql"
    mkdir -p "$_dir"
    _n=1
    while [ -f "$_dir/$(printf '%04d' "$_n").$_engine.sql" ]; do _n=$((_n + 1)); done
    printf '%s\n' "$_sql" > "$_dir/$(printf '%04d' "$_n").$_engine.sql"
}
