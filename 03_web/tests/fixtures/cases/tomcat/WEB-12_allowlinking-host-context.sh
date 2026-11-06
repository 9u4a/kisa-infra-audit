#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 앱별 컨텍스트 디스크립터(conf/Catalina/localhost/kisa.xml)의 allowLinking="true"
#       (1.5.0 A21: 예전에는 server.xml·context.xml 만 봐 GOOD)
# FIX: GOOD 앱별 컨텍스트의 allowLinking 을 "false" 로
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
    <Resources allowLinking="true"/>
</Context>
' > "$TC/conf/Catalina/localhost/kisa.xml"
assert grep -q 'allowLinking="true"' "$TC/conf/Catalina/localhost/kisa.xml"
assert_not grep -q 'allowLinking' "$CX"
assert tc_ok
