#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: UserDatabaseRealm 에 MessageDigestCredentialHandler(SHA-256) + manager-gui 비밀번호를 digest.sh 해시로 저장
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
HASH=$("$TC/bin/digest.sh" -a SHA-256 -h org.apache.catalina.realm.MessageDigestCredentialHandler 'Kisa#Case2026pw' 2>/dev/null | sed -n 's/^.*:\([0-9a-f]*\$[0-9]*\$[0-9a-f]*\)$/\1/p' | tail -n 1)
assert test -n "$HASH"
sed -i 's#resourceName="UserDatabase"/>#resourceName="UserDatabase">\n          <CredentialHandler className="org.apache.catalina.realm.MessageDigestCredentialHandler" algorithm="SHA-256"/>\n        </Realm>#' "$SX"
insert_before "$UX" '</tomcat-users>' "  <user username=\"opsadm\" password=\"$HASH\" roles=\"manager-gui\"/>"
assert grep -q 'algorithm="SHA-256"' "$SX"
assert grep -q "password=\"$HASH\"" "$UX"
assert tc_ok
