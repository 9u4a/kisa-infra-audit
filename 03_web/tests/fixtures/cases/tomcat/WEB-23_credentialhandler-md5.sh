#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: JNDIRealm(LDAP) 의 <CredentialHandler algorithm="MD5"/>(Tomcat 8+ 방식, digest 속성 없음)
#       (1.5.0 A23: 예전에는 digest 속성만 봐 "LDAP Realm 없음" NA)
# FIX: GOOD CredentialHandler algorithm 을 SHA-256 으로
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
               userPattern="uid={0},ou=people,dc=example,dc=com">
          <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="MD5"/>
        </Realm>'
assert grep -q 'algorithm="MD5"' "$SX"
assert_not grep -q 'digest=' "$SX"
assert tc_ok
