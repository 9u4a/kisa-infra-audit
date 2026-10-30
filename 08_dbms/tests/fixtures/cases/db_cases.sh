#!/bin/sh
# 08_dbms/tests/fixtures/cases/db_cases.sh — MySQL/PostgreSQL/Oracle 항목별 판정 양방향 케이스 구현(POSIX sh).
# cases.json 의 (engine, name) 선언과 짝지어 08_dbms/tests/db_case_runner.py 가 DB 서버 컨테이너 안에서 root 로 실행한다
# (로컬 모드 - 설정 파일·프로세스 기반 항목도 서버 안에서 직접 진단). 기대 판정(cases.json expect)은 guide.json 판단기준에서
# 정했다. 운영 서버에서 실행 금지 - DB 계정·권한·설정 파일·재기동을 실제로 바꾼다.
#
#   sh db_cases.sh <engine> ready                              DB 가 접속을 받으면 0
#   sh db_cases.sh <engine> snapshot                           조치 원복 비교용 DB·파일 상태(표준출력)
#   sh db_cases.sh <engine> <case> meta                        MODE=<접속 방식> FIX=<조치 시험 여부> ANSWERS=.. FIXEXPECT=.. RB=..
#   sh db_cases.sh <engine> <case> setup|verify|restore        상태 만들기 / 만든 상태 읽어 확인(0=적용됨) / 되돌리기
#   sh db_cases.sh <engine> <case> run <code>                  run.sh -i <code> 를 케이스 접속 방식으로 실행 → STATUS=<판정>
#   sh db_cases.sh <engine> <case> fix <code>                  fix.sh --apply(가상 터미널로 답 입력) → FIX=<changes.log 상태> RECHECK=..
#   sh db_cases.sh <engine> <case> rollback                    마지막 fix 실행 폴더를 fix.sh --rollback → RB_RC=.. RB_IRREV=..
#
# meta 의 RB: same = 원복 후 snapshot 이 조치 전과 같아야 함 / irreversible = 원복 불가 기록(비밀번호 재설정 등)이 있어야 함.
# 비밀번호는 테스트 전용 값이며 결과물에 남지 않는지는 run_tests.sh 의 운영 안전 단계가 따로 본다.
set -u
ENGINE=$1
CASE=${2:-}
ACTION=${3:-}
CODE=${4:-}
cd /infra || exit 2

ROOTPW='TestRoot123!'
ORAPW='TestRoot123'
ADMPW='KisaAdm#1234'
NEWPW='KisaNew#98765'
WORK=/tmp/kisa_case
mkdir -p "$WORK"
chmod 777 "$WORK" 2>/dev/null

# ---- 엔진별 SQL 실행기(표준입력의 SQL) ----------------------------------------------------------
my() { MYSQL_PWD="$ROOTPW" mysql -uroot -N -B 2>&1; }
my_nopw() { mysql -uroot -N -B 2>&1; }
pg() { psql -U postgres -d postgres -qAtX -v ON_ERROR_STOP=1 2>&1; }
as_oracle() { su oracle -s /bin/sh -c "$1"; }
# ora_pdb / ora_cdb: SYSDBA(OS 인증)로 PDB(FREEPDB1) / CDB 루트에서 실행. 출력은 머리말 없이 | 구분.
ora_run() {
    # sqlplus 는 한 줄에 문장 하나만 받는다(ORA-03405) - "A; B;" 를 줄 단위로 나눈다(케이스 SQL 리터럴에는 "; " 가 없음)
    _sql=$(sed 's/; */;\n/g')
    printf 'whenever sqlerror exit failure\nset heading off feedback off pagesize 0 verify off linesize 500 trimspool on colsep |\n%s\n%s\nexit\n' "$1" "$_sql" \
        > "$WORK/ora.sql"
    chmod 644 "$WORK/ora.sql"
    as_oracle "sqlplus -s / as sysdba @$WORK/ora.sql" 2>&1
}
ora_pdb() { ora_run "alter session set container=FREEPDB1;"; }
ora_cdb() { ora_run ""; }

restart_mysql() {
    service mysqld restart >/dev/null 2>&1
    wait_ready mysql 90
}
restart_pg() {
    service postgresql restart >/dev/null 2>&1
    wait_ready postgres 90
}
restart_ora() {
    printf 'shutdown immediate\nstartup\nalter pluggable database all open;\n' | ora_cdb >/dev/null 2>&1
    wait_ready oracle 240
}

is_ready() {
    case "$1" in
        mysql) MYSQL_PWD="$ROOTPW" mysql -uroot -h127.0.0.1 -N -B -e 'SELECT 1' >/dev/null 2>&1 ;;
        postgres) [ "$(psql -U postgres -h 127.0.0.1 -qAtX -c 'SELECT 1' 2>/dev/null)" = "1" ] ;;
        # Oracle: 계정 로그인 대신 OS 인증으로 PDB 가 열렸는지 + 리스너에 PDB 서비스가 등록됐는지 본다 - os_roles=TRUE(D-19 취약
        # 케이스)에서는 SYSTEM 이 DB 에서 받은 롤을 잃어 로그인 자체가 거부된다(ORA-01045, 실기 확인).
        oracle) [ "$(printf 'SELECT open_mode FROM v$pdbs WHERE name = '"'FREEPDB1'"';\n' | ora_cdb | tr -d ' \t\r' | awk 'NF' | head -n1)" = "READWRITE" ] \
                && as_oracle "lsnrctl status" 2>/dev/null | grep -qi 'Service "freepdb1"' ;;
    esac
}
wait_ready() {
    _w=0
    while [ "$_w" -lt "$2" ]; do
        is_ready "$1" && return 0
        sleep 2; _w=$((_w + 2))
    done
    return 1
}

# ---- 공통: 진단·조치 실행 ---------------------------------------------------------------------------
# MODE: mysql=root|admin, postgres=local, oracle=pdb(SYSTEM@FREEPDB1)|sysdba(OS 인증, CDB 루트)|pdbsys(OS 인증, ORACLE_PDB_SID 로 PDB)
# SYS 소유 객체 권한(D-11/D-17)은 부여자 SYS 만 회수할 수 있어(ORA-01927) 조치 검증은 pdbsys 로 한다.
case_mode() { meta | sed -n 's/^MODE=//p'; }
conn_cmd() {  # conn_cmd <sh 08_dbms/run.sh 또는 fix.sh 뒤에 붙일 나머지 인자> -> 실행할 명령 문자열
    case "$ENGINE:$(case_mode)" in
        mysql:root) printf 'DB_PASSWORD=%s sh %s --user root' "'$ROOTPW'" "$1" ;;
        mysql:admin) printf 'DB_PASSWORD=%s sh %s --user kisa_admin' "'$ADMPW'" "$1" ;;
        mysql:nopw) printf 'DB_PASSWORD= sh %s --user root' "$1" ;;
        postgres:local) printf 'DB_PASSWORD=%s sh %s --user postgres' "'$ROOTPW'" "$1" ;;
        oracle:pdb) printf 'DB_PASSWORD=%s sh %s --host localhost --db FREEPDB1 --user system' "'$ORAPW'" "$1" ;;
        oracle:sysdba) printf 'sh %s' "$1" ;;
        oracle:pdbsys) printf 'ORACLE_PDB_SID=FREEPDB1 sh %s' "$1" ;;
    esac
}
exec_conn() {  # 엔진에 맞는 OS 계정으로 실행(Oracle 은 oracle 계정 - OS 인증·sqlplus)
    if [ "$ENGINE" = "oracle" ]; then as_oracle "cd /infra && $1"; else sh -c "$1"; fi
}
status_of() { sed -n "s/.*\"code\": *\"$2\", *\"status\": *\"\([A-Z]*\)\".*/\1/p" "$1"/*/result.json 2>/dev/null | head -n1; }
do_run() {
    # 같은 초에 두 번 실행해도 결과 폴더가 섞이지 않게 mktemp(예전 이름 규칙은 조치 전·후 결과가 한 폴더에 쌓였다)
    _o=$(mktemp -d "$WORK/run_XXXXXX"); chmod 777 "$_o"
    exec_conn "$(conn_cmd "08_dbms/run.sh -e $ENGINE -i $CODE -o $_o")" >/dev/null 2>&1
    echo "STATUS=$(status_of "$_o" "$CODE")"
    echo "$_o" > "$WORK/last_run"
}
do_fix() {
    do_run >/dev/null
    _r=$(cat "$WORK/last_run")
    _f=$(mktemp -d "$WORK/fix_XXXXXX"); chmod 777 "$_f"
    _ans=$(meta | sed -n 's/^ANSWERS=//p')
    _cmd=$(conn_cmd "08_dbms/fix.sh -e $ENGINE -r $_r/*/result.json -i $CODE --apply --yes -o $_f")
    printf '%s' "$_cmd" > "$WORK/fix_cmd.sh"
    chmod 644 "$WORK/fix_cmd.sh"
    exec_conn "printf '$_ans' | script -qec 'sh $WORK/fix_cmd.sh' /dev/null" > "$WORK/fix.out" 2>&1
    _line=$(awk -F'\t' -v c="$CODE" '$2 == c' "$_f"/*/changes.log 2>/dev/null | tail -n1)
    echo "FIX=$(printf '%s' "$_line" | cut -f4)"
    echo "RECHECK=$(printf '%s' "$_line" | grep -o 'recheck=[A-Z]*' | head -n1 | cut -d= -f2)"
    do_run | sed 's/^STATUS=/AFTER=/'
    ls -d "$_f"/*/ 2>/dev/null | head -n1 > "$WORK/last_fix"
}
do_rollback() {
    _d=$(cat "$WORK/last_fix" 2>/dev/null)
    [ -n "$_d" ] || { echo "RB_RC=nofix"; return; }
    exec_conn "$(conn_cmd "08_dbms/fix.sh -e $ENGINE --rollback $_d")" > "$WORK/rb.out" 2>&1
    echo "RB_RC=$?"
    if grep -q '원복 불가' "$WORK/rb.out"; then echo "RB_IRREV=1"; else echo "RB_IRREV=0"; fi
}

# ---- 원복 비교용 상태 스냅샷 -----------------------------------------------------------------------
file_state() { for _f in "$@"; do [ -e "$_f" ] && echo "$_f $(stat -L -c '%U:%G %a' "$_f") $(md5sum < "$_f" | cut -c1-32)"; done; }
snapshot() {
    case "$ENGINE" in
        mysql)
            my <<'EOF'
SELECT user, host, plugin, account_locked, authentication_string = '' FROM mysql.user ORDER BY user, host;
SELECT user, host, Grant_priv, Select_priv, Process_priv FROM mysql.user ORDER BY user, host;
SELECT * FROM mysql.db ORDER BY user, host, db; SELECT * FROM mysql.tables_priv ORDER BY user, host, db, table_name;
SELECT * FROM mysql.global_grants ORDER BY user, host, priv; SELECT component_urn FROM mysql.component ORDER BY 1;
SHOW GLOBAL VARIABLES WHERE Variable_name LIKE 'validate_password%' OR Variable_name = 'default_password_lifetime';
EOF
            file_state /etc/my.cnf
            # ib_buffer_pool 은 mysqld 가 종료할 때마다 새로 쓰는 캐시 덤프라(구동 계정 소유) 조치의 재기동 순서에 따라
            # 소유자가 달라진다 - 원복 비교에서 뺀다(내용은 다음 기동 때 다시 덤프됨).
            find /var/lib/mysql -xdev -user 0 ! -name ib_buffer_pool 2>/dev/null | sort ;;
        postgres)
            pg <<'EOF'
SELECT rolname, rolsuper, rolcanlogin, rolvaliduntil, rolpassword IS NULL, left(rolpassword, 5) FROM pg_authid ORDER BY rolname;
SELECT name, setting FROM pg_settings WHERE context NOT IN ('postmaster', 'internal') ORDER BY name;
SELECT grantee, count(*) FROM information_schema.role_table_grants WHERE table_schema = 'pg_catalog' GROUP BY 1 ORDER BY 1;
SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules ORDER BY 1;
EOF
            _d=/var/lib/postgresql/data
            file_state "$_d/postgresql.conf" "$_d/pg_hba.conf" "$_d/postgresql.auto.conf" ;;
        oracle)
            ora_pdb <<'EOF'
SELECT username, account_status, profile FROM dba_users ORDER BY username;
SELECT profile, resource_name, limit FROM dba_profiles WHERE resource_type = 'PASSWORD' ORDER BY 1, 2;
SELECT tp.grantee, tp.owner, tp.table_name, tp.privilege, tp.grantable FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE u.oracle_maintained = 'N' ORDER BY 1, 2, 3, 4;
SELECT owner, table_name, grantee, privilege FROM dba_tab_privs WHERE table_name = 'AUD$' ORDER BY 1, 2, 3, 4;
SELECT granted_role FROM dba_role_privs WHERE grantee = 'PUBLIC' ORDER BY 1;
SELECT name, value FROM v$parameter WHERE name = 'resource_limit';
SELECT policy_name FROM audit_unified_enabled_policies ORDER BY 1;
EOF
            ora_cdb <<'EOF'
SELECT name, isspecified, value FROM v$spparameter WHERE name IN ('os_roles', 'remote_os_roles', 'audit_trail', 'resource_limit') ORDER BY 1;
EOF
            _a=$ORACLE_HOME/network/admin
            file_state "$_a/sqlnet.ora" "$_a/listener.ora" ;;
    esac
}

# ---- 케이스 정의 ---------------------------------------------------------------------------------
# meta: MODE / FIX(1=조치 시험) / ANSWERS(fix.sh 가상 터미널 입력, printf 형식) / FIXEXPECT(재검증 기대 판정) / RB
meta() {
    _m=""; _fix=0; _ans='y\n'; _fx=GOOD; _rb=same
    case "$ENGINE:$CASE" in
        mysql:root-empty-password) _m="admin"; _fix=1; _ans="y\ny\n$NEWPW\n$NEWPW\n"; _rb=irreversible ;;
        mysql:no-password-policy) _m=root; _fix=1; _fx=MANUAL ;;
        mysql:validate-password-installed) _m=root ;;
        mysql:mysqld-as-root) _m=root; _fix=1 ;;
        mysql:mysqld-as-mysql) _m=root ;;
        mysql:native-password-account) _m=root; _fix=1; _ans="y\ny\n$NEWPW\n$NEWPW\n"; _rb=irreversible ;;
        mysql:root-any-host) _m=root ;;
        mysql:no-any-host) _m=root ;;
        mysql:mycnf-644) _m=root; _fix=1 ;;
        mysql:mycnf-640) _m=root ;;
        mysql:grant-option-user) _m=root; _fix=1 ;;
        postgres:postgres-no-password) _m=local; _fix=1; _ans="y\ny\n$NEWPW\n$NEWPW\n"; _rb=irreversible ;;
        postgres:no-passwordcheck) _m=local; _fix=1; _fx=MANUAL ;;
        postgres:passwordcheck-loaded) _m=local ;;
        postgres:md5-encryption) _m=local; _fix=1 ;;
        postgres:md5-stored-role) _m=local ;;
        postgres:hba-any-address) _m=local ;;
        postgres:hba-restricted) _m=local ;;
        postgres:conf-perm-644) _m=local; _fix=1 ;;
        postgres:conf-perm-600) _m=local ;;
        postgres:non-admin-owner) _m=local ;;
        postgres:collector-off) _m=local; _fix=1; _fx=MANUAL ;;
        postgres:collector-on) _m=local ;;
        oracle:defpwd-account-open) _m=pdb; _fix=1 ;;
        oracle:defpwd-account-locked) _m=pdb ;;
        oracle:no-password-policy) _m=pdb; _fix=1; _fx=MANUAL ;;
        oracle:password-life-time-set) _m=pdb ;;
        oracle:no-reuse-limit) _m=pdb; _fix=1 ;;
        oracle:reuse-limit-set) _m=pdb ;;
        oracle:pmon-as-root) _m=pdb ;;
        oracle:pmon-as-oracle) _m=pdb ;;
        oracle:no-logon-version) _m=pdb; _fix=1 ;;
        oracle:logon-version-12) _m=pdb ;;
        oracle:failed-login-unlimited) _m=pdb; _fix=1 ;;
        oracle:failed-login-limited) _m=pdb ;;
        oracle:no-validnode-checking) _m=pdb ;;
        oracle:validnode-checking) _m=pdb ;;
        oracle:user-dba-view-grant) _m=pdbsys; _fix=1 ;;
        oracle:no-system-table-grant) _m=pdb ;;
        oracle:sqlnet-world-writable) _m=pdb; _fix=1 ;;
        oracle:net-files-644) _m=pdb ;;
        oracle:no-admin-restrictions) _m=pdb; _fix=1 ;;
        oracle:admin-restrictions-on) _m=pdb ;;
        oracle:aud-grant-user) _m=pdbsys; _fix=1 ;;
        oracle:aud-sys-only) _m=pdb ;;
        oracle:role-to-public) _m=pdb; _fix=1 ;;
        oracle:no-public-role) _m=pdb ;;
        oracle:os-roles-true) _m=sysdba; _fix=1 ;;
        oracle:os-params-false) _m=sysdba ;;
        oracle:non-admin-owner) _m=pdb ;;
        oracle:grantable-user) _m=pdb; _fix=1 ;;
        oracle:no-grantable-user) _m=pdb ;;
        oracle:resource-limit-false) _m=pdb; _fix=1 ;;
        oracle:resource-limit-true) _m=pdb ;;
        oracle:audit-none) _m=sysdba; _fix=1; _fx=MANUAL ;;
        oracle:unified-policy-enabled) _m=pdb ;;
        *) echo "UNKNOWN_CASE=$ENGINE:$CASE"; return 1 ;;
    esac
    printf 'MODE=%s\nFIX=%s\nANSWERS=%s\nFIXEXPECT=%s\nRB=%s\n' "$_m" "$_fix" "$_ans" "$_fx" "$_rb"
}

MYCNF=/etc/my.cnf
PGD=/var/lib/postgresql/data
case_setup() {
    case "$ENGINE:$CASE" in
        # MySQL ---------------------------------------------------------------------------------
        # D-01 취약: 초기 상태(--initialize-insecure)처럼 root@localhost 비밀번호가 비어 있음. 진단·조치는 별도 관리 계정으로.
        mysql:root-empty-password) my <<EOF
CREATE USER 'kisa_admin'@'localhost' IDENTIFIED BY '$ADMPW'; GRANT ALL ON *.* TO 'kisa_admin'@'localhost' WITH GRANT OPTION;
ALTER USER 'root'@'localhost' IDENTIFIED BY '';
EOF
        ;;
        mysql:no-password-policy|mysql:root-any-host|mysql:mycnf-644|mysql:mysqld-as-mysql) : ;;  # 이미지 기본 상태 그대로
        # D-03 수동: validate_password 컴포넌트 설치(값이 기관 정책에 맞는지는 수동 판단)
        mysql:validate-password-installed) echo "INSTALL COMPONENT 'file://component_validate_password';" | my ;;
        # D-07 취약: my.cnf user=root 로 재기동(mysqld 가 root 로 구동)
        mysql:mysqld-as-root) cp -p "$MYCNF" "$WORK/my.cnf.orig"; sed -i 's/^user=mysql$/user=root/' "$MYCNF"; restart_mysql ;;
        # D-08 취약: SHA-1 기반 mysql_native_password 계정(서버는 --mysql-native-password=ON 으로 기동)
        mysql:native-password-account) echo "CREATE USER 'kisa_native'@'localhost' IDENTIFIED WITH mysql_native_password BY 'KisaOld#1234';" | my ;;
        # D-10 양호: 모든 호스트(%) 계정을 특정 IP 로 제한
        mysql:no-any-host) echo "RENAME USER 'root'@'%' TO 'root'@'10.0.0.5';" | my ;;
        # D-14 양호: my.cnf 권한 640
        mysql:mycnf-640) cp -p "$MYCNF" "$WORK/my.cnf.orig"; chmod 640 "$MYCNF"; chgrp mysql "$MYCNF" ;;
        # D-21 취약: 일반 계정에 전역 WITH GRANT OPTION(Role 이 아닌 사용자에게 직접)
        mysql:grant-option-user) echo "CREATE USER 'kisa_go'@'10.0.0.6' IDENTIFIED BY 'KisaGo#1234'; GRANT PROCESS ON *.* TO 'kisa_go'@'10.0.0.6' WITH GRANT OPTION;" | my ;;

        # PostgreSQL ----------------------------------------------------------------------------
        postgres:postgres-no-password) echo "ALTER USER postgres PASSWORD NULL;" | pg ;;
        postgres:no-passwordcheck|postgres:hba-any-address|postgres:conf-perm-600|postgres:collector-off) : ;;
        postgres:passwordcheck-loaded) echo "ALTER SYSTEM SET shared_preload_libraries = 'passwordcheck';" | pg; restart_pg ;;
        postgres:md5-encryption) printf "ALTER SYSTEM SET password_encryption = 'md5';\nSELECT pg_reload_conf();\n" | pg >/dev/null; sleep 1 ;;
        postgres:md5-stored-role) echo "SET password_encryption = 'md5'; CREATE ROLE kisa_md5 LOGIN PASSWORD 'KisaOld#1234';" | pg ;;
        postgres:hba-restricted)
            cp -p "$PGD/pg_hba.conf" "$WORK/pg_hba.conf.orig"
            sed -i -E 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+)all([[:space:]])/\1172.16.0.0\/12\2/' "$PGD/pg_hba.conf"
            echo "SELECT pg_reload_conf();" | pg >/dev/null; sleep 1 ;;
        postgres:conf-perm-644) chmod 644 "$PGD/postgresql.conf" ;;
        postgres:non-admin-owner) echo "CREATE ROLE kisa_app LOGIN; CREATE TABLE public.kisa_app_t (id int); ALTER TABLE public.kisa_app_t OWNER TO kisa_app;" | pg ;;
        postgres:collector-on) echo "ALTER SYSTEM SET logging_collector = on;" | pg; restart_pg ;;

        # Oracle (PDB FREEPDB1) -----------------------------------------------------------------
        # D-01 취약: 데모 계정 SCOTT 가 초기 비밀번호(tiger)·OPEN
        oracle:defpwd-account-open) echo "CREATE USER scott IDENTIFIED BY tiger;" | ora_pdb ;;
        oracle:defpwd-account-locked) echo "CREATE USER scott IDENTIFIED BY tiger ACCOUNT LOCK;" | ora_pdb ;;
        oracle:no-password-policy|oracle:no-reuse-limit|oracle:pmon-as-oracle|oracle:no-logon-version|oracle:failed-login-unlimited) : ;;
        oracle:no-validnode-checking|oracle:no-system-table-grant|oracle:net-files-644|oracle:no-admin-restrictions) : ;;
        oracle:aud-sys-only|oracle:no-public-role|oracle:os-params-false|oracle:no-grantable-user|oracle:resource-limit-true|oracle:audit-none) : ;;
        oracle:password-life-time-set) echo "ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME 90;" | ora_pdb ;;
        oracle:reuse-limit-set) echo "ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME 365 PASSWORD_REUSE_MAX 5;" | ora_pdb ;;
        # D-07 취약(모의): root 가 띄운 pmon 이름의 프로세스. 실제 Oracle 은 root 기동을 거부해 컨테이너에서 재현 불가 -
        # check 는 /proc 의 *pmon* 프로세스 uid 만 보므로 같은 경로를 탄다(KNOWN_ISSUES L-10).
        oracle:pmon-as-root)
            cp /usr/bin/sleep "$WORK/ora_pmon_KISA"
            setsid "$WORK/ora_pmon_KISA" 3600 </dev/null >/dev/null 2>&1 &
            sleep 1 ;;
        oracle:logon-version-12) ora_file_backup sqlnet.ora; printf '\nSQLNET.ALLOWED_LOGON_VERSION_SERVER=12\n' >> "$(ora_target sqlnet.ora)" ;;
        oracle:failed-login-limited) echo "ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS 5;" | ora_pdb ;;
        oracle:validnode-checking) ora_file_backup sqlnet.ora; printf '\ntcp.validnode_checking = yes\ntcp.invited_nodes = (127.0.0.1, localhost)\n' >> "$(ora_target sqlnet.ora)" ;;
        oracle:user-dba-view-grant) echo "CREATE USER kisa_u IDENTIFIED BY \"KisaU#1234\"; GRANT SELECT ON sys.dba_users TO kisa_u;" | ora_pdb ;;
        oracle:sqlnet-world-writable) ora_file_backup sqlnet.ora; chmod 666 "$(ora_target sqlnet.ora)" ;;
        oracle:admin-restrictions-on) ora_file_backup listener.ora; printf '\nADMIN_RESTRICTIONS_LISTENER = ON\n' >> "$(ora_target listener.ora)" ;;
        oracle:aud-grant-user) echo "CREATE USER kisa_u IDENTIFIED BY \"KisaU#1234\"; GRANT SELECT ON sys.aud\$ TO kisa_u;" | ora_pdb ;;
        oracle:role-to-public) echo "CREATE ROLE kisa_r; GRANT kisa_r TO PUBLIC;" | ora_pdb ;;
        oracle:os-roles-true) echo "ALTER SYSTEM SET os_roles = TRUE SCOPE=SPFILE;" | ora_cdb; restart_ora ;;
        oracle:non-admin-owner) echo "CREATE USER kisa_own IDENTIFIED BY \"KisaO#1234\" QUOTA 1M ON users; CREATE TABLE kisa_own.t (id NUMBER);" | ora_pdb ;;
        oracle:grantable-user) echo "CREATE USER kisa_own IDENTIFIED BY \"KisaO#1234\" QUOTA 1M ON users; CREATE TABLE kisa_own.t (id NUMBER); CREATE USER kisa_u IDENTIFIED BY \"KisaU#1234\"; GRANT SELECT ON kisa_own.t TO kisa_u WITH GRANT OPTION;" | ora_pdb ;;
        oracle:resource-limit-false) echo "ALTER SYSTEM SET resource_limit = FALSE;" | ora_pdb ;;
        oracle:unified-policy-enabled) echo "AUDIT POLICY ORA_LOGON_FAILURES;" | ora_pdb ;;
        *) echo "UNKNOWN_CASE=$ENGINE:$CASE"; return 1 ;;
    esac
}

# verify: 만든(또는 기본) 상태를 실제로 읽어 확인한다 - 0 이 아니면 러너가 FAIL(설정이 안 먹었는데 기본값으로 통과하는 것 방지)
case_verify() {
    case "$ENGINE:$CASE" in
        mysql:root-empty-password) [ "$(echo "SELECT authentication_string FROM mysql.user WHERE user='root' AND host='localhost';" | my_nopw)" = "" ] \
            && echo "SELECT 1;" | my_nopw >/dev/null ;;
        mysql:no-password-policy) [ -z "$(echo "SELECT component_urn FROM mysql.component WHERE component_urn LIKE '%validate_password%';" | my)" ] \
            && [ "$(echo "SELECT @@default_password_lifetime;" | my)" = "0" ] ;;
        mysql:validate-password-installed) [ -n "$(echo "SHOW VARIABLES LIKE 'validate_password.policy';" | my)" ] ;;
        mysql:mysqld-as-root|mysql:mysqld-as-mysql)
            _want=999; [ "$CASE" = "mysqld-as-root" ] && _want=0
            for _p in /proc/[0-9]*; do
                [ "$(cat "$_p/comm" 2>/dev/null)" = "mysqld" ] && [ "$(awk '/^Uid:/ {print $2}' "$_p/status")" = "$_want" ] && return 0
            done
            return 1 ;;
        mysql:native-password-account) [ "$(echo "SELECT plugin FROM mysql.user WHERE user='kisa_native';" | my)" = "mysql_native_password" ] ;;
        mysql:root-any-host) [ -n "$(echo "SELECT user FROM mysql.user WHERE host='%';" | my)" ] ;;
        mysql:no-any-host) [ -z "$(echo "SELECT user FROM mysql.user WHERE host='%';" | my)" ] ;;
        mysql:mycnf-644) [ "$(stat -c '%a' "$MYCNF")" = "644" ] ;;
        mysql:mycnf-640) [ "$(stat -c '%a' "$MYCNF")" = "640" ] ;;
        mysql:grant-option-user) [ "$(echo "SELECT Grant_priv FROM mysql.user WHERE user='kisa_go';" | my)" = "Y" ] ;;

        postgres:postgres-no-password) [ "$(echo "SELECT rolpassword IS NULL FROM pg_authid WHERE rolname='postgres';" | pg)" = "t" ] ;;
        postgres:no-passwordcheck) ! echo "SHOW shared_preload_libraries;" | pg | grep -q passwordcheck ;;
        postgres:passwordcheck-loaded) echo "SHOW shared_preload_libraries;" | pg | grep -q passwordcheck ;;
        postgres:md5-encryption) [ "$(echo "SHOW password_encryption;" | pg)" = "md5" ] ;;
        postgres:md5-stored-role) [ "$(echo "SELECT left(rolpassword, 3) FROM pg_authid WHERE rolname='kisa_md5';" | pg)" = "md5" ] \
            && [ "$(echo "SHOW password_encryption;" | pg)" = "scram-sha-256" ] ;;
        postgres:hba-any-address) [ "$(echo "SELECT count(*) FROM pg_hba_file_rules WHERE type = 'host' AND address = 'all';" | pg)" != "0" ] ;;
        postgres:hba-restricted) [ "$(echo "SELECT count(*) FROM pg_hba_file_rules WHERE type LIKE 'host%' AND (address IS NULL OR address IN ('all', '0.0.0.0', '::'));" | pg)" = "0" ] \
            && [ "$(echo "SELECT count(*) FROM pg_hba_file_rules WHERE address = '172.16.0.0';" | pg)" != "0" ] ;;
        postgres:conf-perm-644) [ "$(stat -c '%a' "$PGD/postgresql.conf")" = "644" ] ;;
        postgres:conf-perm-600) [ "$(stat -c '%a' "$PGD/postgresql.conf")" = "600" ] && [ "$(stat -c '%a' "$PGD/pg_hba.conf")" = "600" ] ;;
        postgres:non-admin-owner) [ "$(echo "SELECT tableowner FROM pg_tables WHERE tablename='kisa_app_t';" | pg)" = "kisa_app" ] ;;
        postgres:collector-off) [ "$(echo "SHOW logging_collector;" | pg)" = "off" ] ;;
        postgres:collector-on) [ "$(echo "SHOW logging_collector;" | pg)" = "on" ] ;;

        oracle:defpwd-account-open) ora_has "SELECT u.account_status FROM dba_users u JOIN dba_users_with_defpwd d ON d.username = u.username WHERE u.username = 'SCOTT';" OPEN ;;
        oracle:defpwd-account-locked) ora_has "SELECT u.account_status FROM dba_users u JOIN dba_users_with_defpwd d ON d.username = u.username WHERE u.username = 'SCOTT';" LOCKED ;;
        oracle:no-password-policy) ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'PASSWORD_LIFE_TIME';" UNLIMITED \
            && ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'PASSWORD_VERIFY_FUNCTION';" NULL ;;
        oracle:password-life-time-set) ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'PASSWORD_LIFE_TIME';" 90 ;;
        oracle:no-reuse-limit) ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'PASSWORD_REUSE_MAX';" UNLIMITED ;;
        oracle:reuse-limit-set) ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'PASSWORD_REUSE_MAX';" 5 ;;
        oracle:pmon-as-root|oracle:pmon-as-oracle)
            _found=""
            for _p in /proc/[0-9]*; do
                case "$(cat "$_p/comm" 2>/dev/null)" in *pmon*) _found="$_found $(awk '/^Uid:/ {print $2}' "$_p/status")" ;; esac
            done
            if [ "$CASE" = "pmon-as-root" ]; then case " $_found " in *" 0 "*) return 0 ;; esac; return 1; fi
            [ -n "$_found" ] && case " $_found " in *" 0 "*) return 1 ;; esac ;;
        oracle:no-logon-version) ! grep -qi 'ALLOWED_LOGON_VERSION_SERVER' "$(ora_target sqlnet.ora)" ;;
        oracle:logon-version-12) grep -q '^SQLNET.ALLOWED_LOGON_VERSION_SERVER=12$' "$(ora_target sqlnet.ora)" ;;
        oracle:failed-login-unlimited) ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'FAILED_LOGIN_ATTEMPTS';" UNLIMITED ;;
        oracle:failed-login-limited) ora_has "SELECT limit FROM dba_profiles WHERE profile = 'DEFAULT' AND resource_name = 'FAILED_LOGIN_ATTEMPTS';" 5 ;;
        oracle:no-validnode-checking) ! grep -qi 'validnode_checking' "$(ora_target sqlnet.ora)" ;;
        oracle:validnode-checking) grep -q '^tcp.validnode_checking = yes$' "$(ora_target sqlnet.ora)" ;;
        oracle:user-dba-view-grant) ora_has "SELECT privilege FROM dba_tab_privs WHERE grantee = 'KISA_U' AND table_name = 'DBA_USERS';" SELECT ;;
        oracle:no-system-table-grant) ora_has "SELECT COUNT(*) FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE u.oracle_maintained = 'N' AND tp.owner = 'SYS';" 0 ;;
        oracle:sqlnet-world-writable) [ "$(stat -L -c '%a' "$(ora_target sqlnet.ora)")" = "666" ] ;;
        oracle:net-files-644) [ "$(stat -L -c '%a' "$(ora_target sqlnet.ora)")" = "644" ] && [ "$(stat -L -c '%a' "$(ora_target listener.ora)")" = "644" ] ;;
        oracle:no-admin-restrictions) ! grep -qi 'ADMIN_RESTRICTIONS' "$(ora_target listener.ora)" ;;
        oracle:admin-restrictions-on) grep -q '^ADMIN_RESTRICTIONS_LISTENER = ON$' "$(ora_target listener.ora)" ;;
        oracle:aud-grant-user) ora_has "SELECT privilege FROM dba_tab_privs WHERE grantee = 'KISA_U' AND table_name = 'AUD\$';" SELECT ;;
        oracle:aud-sys-only) ora_has "SELECT COUNT(*) FROM dba_tab_privs WHERE table_name = 'AUD\$' AND grantee NOT IN ('SYS', 'SYSTEM');" 0 ;;
        oracle:role-to-public) ora_has "SELECT granted_role FROM dba_role_privs WHERE grantee = 'PUBLIC';" KISA_R ;;
        oracle:no-public-role) ora_has "SELECT COUNT(*) FROM dba_role_privs WHERE grantee = 'PUBLIC';" 0 ;;
        oracle:os-roles-true) ora_has_cdb "SELECT value FROM v\$parameter WHERE name = 'os_roles';" TRUE ;;
        oracle:os-params-false) ora_has_cdb "SELECT COUNT(*) FROM v\$parameter WHERE name IN ('os_roles', 'remote_os_authent', 'remote_os_roles') AND value = 'TRUE';" 0 ;;
        oracle:non-admin-owner) ora_has "SELECT owner FROM dba_tables WHERE table_name = 'T' AND owner = 'KISA_OWN';" KISA_OWN ;;
        oracle:grantable-user) ora_has "SELECT grantable FROM dba_tab_privs WHERE grantee = 'KISA_U' AND table_name = 'T';" YES ;;
        oracle:no-grantable-user) ora_has "SELECT COUNT(*) FROM dba_tab_privs tp JOIN dba_users u ON u.username = tp.grantee WHERE u.oracle_maintained = 'N' AND tp.grantable = 'YES';" 0 ;;
        oracle:resource-limit-false) ora_has "SELECT value FROM v\$parameter WHERE name = 'resource_limit';" FALSE ;;
        oracle:resource-limit-true) ora_has "SELECT value FROM v\$parameter WHERE name = 'resource_limit';" TRUE ;;
        oracle:audit-none) ora_has_cdb "SELECT value FROM v\$parameter WHERE name = 'audit_trail';" NONE \
            && ora_has_cdb "SELECT COUNT(*) FROM audit_unified_enabled_policies;" 0 ;;
        oracle:unified-policy-enabled) ora_has "SELECT policy_name FROM audit_unified_enabled_policies;" ORA_LOGON_FAILURES ;;
        *) return 1 ;;
    esac
}

case_restore() {
    case "$ENGINE:$CASE" in
        mysql:root-empty-password)
            # 조치가 root 비밀번호를 바꿨으면 그 값으로, 아니면 빈 비밀번호로 접속해 원래 값으로 되돌린다
            { echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOTPW';" | my_nopw >/dev/null 2>&1; } \
                || echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOTPW';" | MYSQL_PWD="$NEWPW" mysql -uroot -N -B >/dev/null 2>&1
            echo "DROP USER IF EXISTS 'kisa_admin'@'localhost';" | my ;;
        mysql:no-password-policy)
            echo "UNINSTALL COMPONENT 'file://component_validate_password';" | my >/dev/null 2>&1
            echo "SET PERSIST default_password_lifetime = 0; RESET PERSIST default_password_lifetime;" | my >/dev/null 2>&1 ; : ;;
        mysql:validate-password-installed) echo "UNINSTALL COMPONENT 'file://component_validate_password';" | my ;;
        mysql:mysqld-as-root) cp -p "$WORK/my.cnf.orig" "$MYCNF"; chown -R mysql:mysql /var/lib/mysql; restart_mysql ;;
        mysql:native-password-account) echo "DROP USER IF EXISTS 'kisa_native'@'localhost';" | my ;;
        mysql:no-any-host) echo "RENAME USER 'root'@'10.0.0.5' TO 'root'@'%';" | my ;;
        mysql:mycnf-640|mysql:mycnf-644) [ -f "$WORK/my.cnf.orig" ] && cp -p "$WORK/my.cnf.orig" "$MYCNF"; chmod 644 "$MYCNF"; chown root:root "$MYCNF" ;;
        mysql:grant-option-user) echo "DROP USER IF EXISTS 'kisa_go'@'10.0.0.6';" | my ;;
        mysql:*) : ;;

        postgres:postgres-no-password) echo "ALTER USER postgres PASSWORD '$ROOTPW';" | pg ;;
        postgres:no-passwordcheck|postgres:passwordcheck-loaded)
            echo "ALTER SYSTEM RESET shared_preload_libraries;" | pg
            [ "$CASE" = "passwordcheck-loaded" ] || echo "SHOW shared_preload_libraries;" | pg | grep -q passwordcheck && restart_pg ; : ;;
        postgres:md5-encryption) printf "ALTER SYSTEM RESET password_encryption;\nSELECT pg_reload_conf();\n" | pg >/dev/null; sleep 1 ;;
        postgres:md5-stored-role) echo "DROP ROLE IF EXISTS kisa_md5;" | pg ;;
        postgres:hba-restricted) cp -p "$WORK/pg_hba.conf.orig" "$PGD/pg_hba.conf"; echo "SELECT pg_reload_conf();" | pg >/dev/null; sleep 1 ;;
        postgres:conf-perm-644|postgres:conf-perm-600) chmod 600 "$PGD/postgresql.conf" "$PGD/pg_hba.conf"; chown postgres:postgres "$PGD/postgresql.conf" "$PGD/pg_hba.conf" ;;
        postgres:non-admin-owner) echo "DROP TABLE IF EXISTS public.kisa_app_t; DROP ROLE IF EXISTS kisa_app;" | pg ;;
        postgres:collector-off|postgres:collector-on)
            printf "ALTER SYSTEM RESET logging_collector;\nALTER SYSTEM RESET log_statement;\nSELECT pg_reload_conf();\n" | pg >/dev/null
            [ "$(echo "SHOW logging_collector;" | pg)" = "off" ] || restart_pg ;;
        postgres:*) : ;;

        oracle:defpwd-account-open|oracle:defpwd-account-locked) echo "DROP USER scott CASCADE;" | ora_pdb ;;
        oracle:no-password-policy|oracle:password-life-time-set) echo "ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED PASSWORD_VERIFY_FUNCTION NULL;" | ora_pdb ;;
        oracle:no-reuse-limit|oracle:reuse-limit-set) echo "ALTER PROFILE DEFAULT LIMIT PASSWORD_REUSE_TIME UNLIMITED PASSWORD_REUSE_MAX UNLIMITED;" | ora_pdb ;;
        oracle:failed-login-unlimited|oracle:failed-login-limited) echo "ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED;" | ora_pdb ;;
        oracle:pmon-as-root) pkill -f "$WORK/ora_pmon_KISA"; rm -f "$WORK/ora_pmon_KISA" ;;
        oracle:no-logon-version|oracle:logon-version-12|oracle:no-validnode-checking|oracle:validnode-checking|oracle:sqlnet-world-writable) ora_file_restore sqlnet.ora ;;
        oracle:no-admin-restrictions|oracle:admin-restrictions-on) ora_file_restore listener.ora ;;
        oracle:user-dba-view-grant|oracle:aud-grant-user) echo "DROP USER kisa_u CASCADE;" | ora_pdb ;;
        oracle:role-to-public) echo "DROP ROLE kisa_r;" | ora_pdb ;;
        oracle:os-roles-true|oracle:os-params-false)
            echo "ALTER SYSTEM RESET os_roles SCOPE=SPFILE;" | ora_cdb >/dev/null 2>&1
            ora_has_cdb "SELECT value FROM v\$parameter WHERE name = 'os_roles';" FALSE || restart_ora ; : ;;
        oracle:non-admin-owner) echo "DROP USER kisa_own CASCADE;" | ora_pdb ;;
        oracle:grantable-user) echo "DROP USER kisa_u CASCADE; DROP USER kisa_own CASCADE;" | ora_pdb ;;
        oracle:resource-limit-false|oracle:resource-limit-true) echo "ALTER SYSTEM SET resource_limit = TRUE;" | ora_pdb ;;
        oracle:audit-none)
            echo "ALTER SYSTEM RESET audit_trail SCOPE=SPFILE;" | ora_cdb >/dev/null 2>&1
            ora_has_cdb "SELECT value FROM v\$parameter WHERE name = 'audit_trail';" NONE || restart_ora
            rm -f "$ORACLE_HOME"/dbs/kisa_D-*.ora ; : ;;
        oracle:unified-policy-enabled) echo "NOAUDIT POLICY ORA_LOGON_FAILURES;" | ora_pdb ;;
        oracle:*) : ;;
    esac
}

# ---- Oracle 보조 ------------------------------------------------------------------------------------
ora_has() { [ "$(printf '%s\n' "$1" | ora_pdb | tr -d ' \t\r' | awk 'NF' | head -n1)" = "$2" ]; }
ora_has_cdb() { [ "$(printf '%s\n' "$1" | ora_cdb | tr -d ' \t\r' | awk 'NF' | head -n1)" = "$2" ]; }
# sqlnet.ora/listener.ora 는 oradata/dbconfig 의 실제 파일을 가리키는 심볼릭 링크다 - 내용·권한은 대상 파일 기준
ora_target() { readlink -f "$ORACLE_HOME/network/admin/$1"; }
ora_file_backup() { [ -f "$WORK/$1.orig" ] || cp -p "$(ora_target "$1")" "$WORK/$1.orig"; }
ora_file_restore() {
    _t=$(ora_target "$1")
    [ -f "$WORK/$1.orig" ] && cp -p "$WORK/$1.orig" "$_t"
    chmod 644 "$_t"; chown oracle:oinstall "$_t"
}
# 원본은 컨테이너 기동 직후 한 번만 보존한다(ready 단계) - 케이스마다 덮어쓰지 않게 이미 있으면 유지
ora_pristine() { for _n in sqlnet.ora listener.ora; do [ -f "$WORK/$_n.orig" ] || cp -p "$(ora_target "$_n")" "$WORK/$_n.orig"; done; }

case "$CASE" in
    ready) wait_ready "$ENGINE" "${3:-5}" || exit 1; [ "$ENGINE" = "oracle" ] && ora_pristine; exit 0 ;;
    snapshot) snapshot; exit 0 ;;
esac
case "$ACTION" in
    meta) meta ;;
    setup) case_setup ;;
    verify) case_verify ;;
    restore) case_restore ;;
    run) do_run ;;
    fix) do_fix ;;
    rollback) do_rollback ;;
    *) echo "usage: db_cases.sh <engine> <case> <meta|setup|verify|restore|run|fix|rollback> [code]" >&2; exit 2 ;;
esac
