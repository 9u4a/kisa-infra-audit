#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: JNDIRealm(LDAP) digest="SHA-256"
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
insert_after "$SX" '<Realm className="org.apache.catalina.realm.LockOutRealm">' '        <Realm className="org.apache.catalina.realm.JNDIRealm" connectionURL="ldap://127.0.0.1:389"
               userPattern="uid={0},ou=people,dc=example,dc=com" digest="SHA-256"/>'
assert grep -q 'digest="SHA-256"' "$SX"
assert tc_ok
