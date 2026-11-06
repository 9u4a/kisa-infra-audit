#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 앱별 컨텍스트 디스크립터(conf/Catalina/localhost/kisa.xml)에 DB 연결 리소스(jdbc DataSource)가 있고 644
#       (1.5.0 A21: 예전에는 server.xml·context.xml 만 봐 "DB 리소스 없음" NA)
# FIX: GOOD 해당 파일을 600 으로
. 03_web/tests/fixtures/cases/case_lib.sh
TC=/usr/local/tomcat
SX=$TC/conf/server.xml
WX=$TC/conf/web.xml
UX=$TC/conf/tomcat-users.xml
CX=$TC/conf/context.xml
tc_ok() {
    mkdir -p /tmp/kisa_cb/logs /tmp/kisa_cb/temp /tmp/kisa_cb/work
    ln -sfn "$TC/conf" /tmp/kisa_cb/conf
    CATALINA_BASE=/tmp/kisa_cb "$TC/bin/catalina.sh" configtest >/tmp/kisa_cb/configtest.log 2>&1
}
mkdir -p "$TC/conf/Catalina/localhost"
printf '<?xml version="1.0" encoding="UTF-8"?>
<Context>
    <Resource name="jdbc/app" auth="Container" type="javax.sql.DataSource" url="jdbc:mysql://db:3306/app" username="app" password="Kisa#Case2026db"/>
</Context>
' > "$TC/conf/Catalina/localhost/kisa.xml"
chmod 644 "$TC/conf/Catalina/localhost/kisa.xml"
assert grep -q 'jdbc/app' "$TC/conf/Catalina/localhost/kisa.xml"
assert_not grep -q 'javax.sql.DataSource' "$SX" "$CX"
assert tc_ok
