#!/bin/sh
# 08_dbms/tests/fixtures/setup.sh <mysql|postgres> <vuln|hardened>
# 클라이언트 컨테이너 안에서 실행되어 DB_HOST 로 지정된 DB 서버에 접속해 상태를 만든다.
# D-11(시스템 테이블 접근 제한)만 명시적으로 다룬다 - 기본 상태(계정 하나만 있음)가 이미
# 양호이므로 hardened=아무 것도 안 함, vuln=일반 계정을 만들고 시스템 테이블 권한을 부여.
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
                FLUSH PRIVILEGES;
            "
        fi
        ;;
    postgres)
        if [ "$MODE" = "vuln" ]; then
            PGPASSWORD="$DB_PASSWORD" psql -h "$HOST" -U postgres -d postgres -c "
                CREATE USER testuser WITH PASSWORD 'TestPass123!';
                GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO testuser;
            "
        fi
        ;;
    *)
        echo "usage: setup.sh <mysql|postgres> <vuln|hardened>" >&2
        exit 2
        ;;
esac
