#!/bin/sh
# 03_web/tests/fixtures/setup.sh <apache|apache-debian|nginx|tomcat> <vuln|hardened>
#
# 데몬 프로세스는 실제로 띄우지 않는다(설정 파일 판정 위주 항목만 다룸 - 01_unix/CLAUDE.md
# 와 같은 이유로 범위를 제한한다). WEB-04(디렉터리 리스팅)만 명시적으로 다루며, 나머지
# 항목은 각 공식 이미지의 있는 그대로의 기본값을 반영한다.
#
# 흥미로운 비대칭: 공식 httpd:2.4 이미지는 기본 설정 자체가 "Options Indexes"로 이미 취약
# (vuln = 기본값 그대로, hardened = 명시적으로 끔)인 반면, nginx/tomcat 공식 이미지는 기본값이
# 이미 양호(autoindex/listings 모두 off/false)라 vuln = 명시적으로 켬, hardened = 기본값 그대로
# - 세 엔진의 기본 보안 태세가 다르다는 것 자체가 실제로 흥미로운 관찰이었다.
set -eu
ENGINE=$1
MODE=$2

case "$ENGINE" in
    apache)
        CONF=/usr/local/apache2/conf/httpd.conf
        if [ "$MODE" = "hardened" ]; then
            sed -i 's/^\([[:space:]]*\)Options Indexes FollowSymLinks/\1Options -Indexes FollowSymLinks/' "$CONF"
        fi
        # S5(run_safety): 진단 증적(WEB-10 ProxyPass 줄)에 URL 비밀번호 원문이 남지 않는지 - 특수문자(#,!) 포함.
        # proxy 모듈이 로드되지 않은 기본 이미지에서도 문법 검사(fix_safety)가 통과하도록 IfModule 로 감싼다.
        if [ "$MODE" = "vuln" ]; then
            printf '<IfModule proxy_module>\n    ProxyPass "/kisaleak" "http://svc:Px9#Leak!Pw@127.0.0.1:9/"\n</IfModule>\n' >> "$CONF"
        fi
        ;;
    apache-debian)
        # Debian 패키지 레이아웃(WEB-R1 회귀): 메인 설정(apache2.conf)의 /var/www Indexes 는 양쪽 모두 끄고,
        # vuln 은 sites-enabled 가상호스트 안의 "Options Indexes" 와 mods-enabled 의 dav/dav_fs(a2enmod 와
        # 같은 심볼릭 링크)로만 취약하게 만든다 - Include 체인을 따라가지 못하면 WEB-04/18 이 거짓 GOOD.
        CONF=/etc/apache2/apache2.conf
        sed -i 's/^\([[:space:]]*\)Options Indexes FollowSymLinks/\1Options FollowSymLinks/' "$CONF"
        if [ "$MODE" = "vuln" ]; then
            VHOST=/etc/apache2/sites-available/000-default.conf
            sed -i 's#^</VirtualHost>#\t<Directory /var/www/html>\n\t\tOptions Indexes\n\t</Directory>\n</VirtualHost>#' "$VHOST"
            for m in dav.load dav_fs.load dav_fs.conf; do
                [ -e "/etc/apache2/mods-enabled/$m" ] || ln -s "../mods-available/$m" "/etc/apache2/mods-enabled/$m"
            done
            # S5: 가상호스트의 ProxyPass URL 비밀번호(위 apache 와 같은 이유, 링크 대상인 sites-available 에 넣음)
            sed -i 's|^</VirtualHost>|\t<IfModule proxy_module>\n\t\tProxyPass "/kisaleak" "http://svc:Px9#Leak!Pw@127.0.0.1:9/"\n\t</IfModule>\n</VirtualHost>|' "$VHOST"
        fi
        ;;
    nginx)
        CONF=/etc/nginx/nginx.conf
        if [ "$MODE" = "vuln" ]; then
            sed -i '/http[[:space:]]*{/a\    autoindex on;' "$CONF"
            # S5: proxy_pass 쿼리의 토큰 원문이 진단 증적(WEB-10)에 남지 않는지 - 특수문자(!) 포함
            sed -i '/http[[:space:]]*{/a\    server { listen 127.0.0.1:8099; location /kisaleak { proxy_pass http://127.0.0.1:9/api?access_token=Nx7-Leak!Tok; } }' "$CONF"
        fi
        ;;
    tomcat)
        WEBXML=/usr/local/tomcat/conf/web.xml
        USERS=/usr/local/tomcat/conf/tomcat-users.xml
        if [ "$MODE" = "vuln" ]; then
            sed -i '0,/<param-value>false<\/param-value>/s//<param-value>true<\/param-value>/' "$WEBXML"
        fi
        # WEB-01: vuln=기본 계정명(tomcat), hardened=기본값 아님. 비밀번호에 '>' 와 '/' 를 넣어
        # 증적에 비밀번호 원문이 실리던 버그(속성 사이를 [^/]* 로 통째로 잡음)와 '>' 에서 요소가
        # 잘려 계정을 놓치던 문제를 재현한다 - run_tests.sh 가 결과물에 이 문자열이 없는지 확인.
        # WEB-08/09/10/16(진단 검수 WEB-R9/R10): Connector 에 keystorePass 를 넣어 증적(WEB-10 proxyName 줄,
        # WEB-16 server= 줄)에 원문이 남지 않는지(run_tests.sh 가 KsLeak9Pass 검사), maxPostSize="-1"(무제한)이
        # VULN 인지 확인한다. hardened 는 10MB 제한 + server 배너 숨김.
        SERVERXML=/usr/local/tomcat/conf/server.xml
        if [ "$MODE" = "vuln" ]; then
            sed -i 's#<Connector port="8080"#<Connector port="8080" maxPostSize="-1" proxyName="px.example.com" keystorePass="KsLeak9Pass"#' "$SERVERXML"
        else
            sed -i 's#<Connector port="8080"#<Connector port="8080" maxPostSize="10485760" server="WebServer" keystorePass="KsLeak9Pass"#' "$SERVERXML"
        fi
        if [ "$MODE" = "vuln" ]; then
            sed -i 's#</tomcat-users>#  <user username="tomcat" password="Leak>Check/Pw9" roles="manager-gui"/>\n</tomcat-users>#' "$USERS"
        else
            sed -i 's#</tomcat-users>#  <user username="ops_admin" password="Leak>CheckPw9Strong" roles="manager-gui"/>\n</tomcat-users>#' "$USERS"
        fi
        ;;
    *)
        echo "usage: setup.sh <apache|apache-debian|nginx|tomcat> <vuln|hardened>" >&2
        exit 2
        ;;
esac
