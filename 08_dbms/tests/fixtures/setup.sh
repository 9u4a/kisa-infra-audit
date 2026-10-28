#!/bin/sh
# 08_dbms/tests/fixtures/setup.sh <mysql|postgres> <vuln|hardened>
# 클라이언트 컨테이너 안에서 실행되어 DB_HOST 로 지정된 DB 서버에 접속해 상태를 만든다.
# D-11(시스템 테이블 접근 제한)만 명시적으로 다룬다 - 기본 상태(계정 하나만 있음)가 이미
# 양호이므로 hardened=아무 것도 안 함, vuln=일반 계정을 만들고 시스템 테이블 권한을 부여.
# vuln 에서는 권한 없는 계정(lowpriv)도 만든다 - run_tests.sh 가 이 계정으로 한 번 더 진단해 권한 부족
# 항목이 GOOD/VULN 대신 ERROR 로 나오는지 확인한다(진단 검수 D-R2).
set -eu
ENGINE=$1
MODE=$2
HOST=${DB_HOST:-dbhost}

case "$ENGINE" in
    mysql)
        if [ "$MODE" = "vuln" ]; then
            mysql -h "$HOST" -uroot "-p${DB_PASSWORD}" -e "
                CREATE USER IF NOT EXISTS 'testuser'@'%' IDENTIFIED BY 'TestPass123!';
                GRANT SELECT ON mysql.* TO 'testuser'@'%';
                CREATE USER IF NOT EXISTS 'lowpriv'@'%' IDENTIFIED BY 'LowPriv123!';
                FLUSH PRIVILEGES;
            "
        fi
        ;;
    postgres)
        if [ "$MODE" = "vuln" ]; then
            PGPASSWORD="$DB_PASSWORD" psql -h "$HOST" -U postgres -d postgres -c "
                CREATE USER testuser WITH PASSWORD 'TestPass123!';
                GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO testuser;
                CREATE USER lowpriv WITH PASSWORD 'LowPriv123!';
            "
        fi
        ;;
    *)
        echo "usage: setup.sh <mysql|postgres> <vuln|hardened>" >&2
        exit 2
        ;;
esac
