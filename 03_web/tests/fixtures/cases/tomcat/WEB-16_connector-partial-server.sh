#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: 8080 Connector 에만 server="WebServer" - 추가한 8081 HTTP Connector 는 기본 배너
#       (1.5.0 A22: 예전에는 Connector 하나에만 server= 가 있어도 GOOD)
# FIX: GOOD server 속성 없는 HTTP Connector 마다 server="WebServer" 추가
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
sed -i 's#<Connector port="8080"#<Connector port="8080" server="WebServer"#' "$SX"
insert_before "$SX" '<Engine name="Catalina" defaultHost="localhost">' '    <Connector port="8081" protocol="HTTP/1.1"
               connectionTimeout="20000" maxPostSize="10485760" />'
assert grep -q '<Connector port="8080" server="WebServer"' "$SX"
assert grep -q '<Connector port="8081"' "$SX"
# 주석(server.xml 의 jvmRoute 예시 등) 밖에 들어갔는지 - 주석 안이면 실제로는 없는 Connector 다
assert sh -c '. lib/common.sh >/dev/null 2>&1; strip_xml_comments "$1" | grep -q "port=\"8081\""' _ "$SX"
assert tc_ok
