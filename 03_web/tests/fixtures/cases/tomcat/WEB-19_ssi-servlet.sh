#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: SSIServlet 정의·매핑 활성(SSI 사용)
# FIX: NONE web.xml 의 다중 줄 servlet 블록 제거는 자동 조치 미지원(ERROR·수동 조치 안내, 설정 무변경)
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
insert_before "$WX" '</web-app>' '    <servlet>
        <servlet-name>ssi</servlet-name>
        <servlet-class>org.apache.catalina.ssi.SSIServlet</servlet-class>
        <load-on-startup>4</load-on-startup>
    </servlet>
    <servlet-mapping>
        <servlet-name>ssi</servlet-name>
        <url-pattern>*.shtml</url-pattern>
    </servlet-mapping>'
assert grep -q 'org.apache.catalina.ssi.SSIServlet' "$WX"
assert tc_ok
