#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# VULN: Tomcat 인스턴스 두 개 중 하나는 전용 계정, 하나는 root 로 구동(가짜 Bootstrap 프로세스로 재현)
#       (1.5.0 A23: 예전에는 비 root 프로세스가 하나라도 있으면 엔진 전체를 GOOD)
# FIX: SKIP 가짜 프로세스(sh 를 java 이름으로 복사)로 만든 상태라 실행 계정 전환 조치를 검증할 대상이 없음
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
useradd -r -M -s /usr/sbin/nologin kisatc
mkdir -p /tmp/kisa_fake
cp /bin/sh /tmp/kisa_fake/java
chmod 755 /tmp/kisa_fake /tmp/kisa_fake/java
runuser -u kisatc -- /tmp/kisa_fake/java -c 'sleep 600; :' org.apache.catalina.startup.Bootstrap >/dev/null 2>&1 &
/tmp/kisa_fake/java -c 'sleep 600; :' org.apache.catalina.startup.Bootstrap >/dev/null 2>&1 &
wait_until 5 sh -c '. 03_web/tests/fixtures/cases/case_lib.sh; [ "$(tomcat_uids | sort -u | wc -l)" -eq 2 ]'
assert sh -c '. 03_web/tests/fixtures/cases/case_lib.sh; tomcat_uids | grep -qx 0'
assert sh -c '. 03_web/tests/fixtures/cases/case_lib.sh; tomcat_uids | grep -qvx 0'
