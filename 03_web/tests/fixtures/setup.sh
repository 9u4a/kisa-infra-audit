#!/bin/sh
# 03_web/tests/fixtures/setup.sh <apache|nginx|tomcat> <vuln|hardened>
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
        ;;
    nginx)
        CONF=/etc/nginx/nginx.conf
        if [ "$MODE" = "vuln" ]; then
            sed -i '/http[[:space:]]*{/a\    autoindex on;' "$CONF"
        fi
        ;;
    tomcat)
        WEBXML=/usr/local/tomcat/conf/web.xml
        if [ "$MODE" = "vuln" ]; then
            sed -i '0,/<param-value>false<\/param-value>/s//<param-value>true<\/param-value>/' "$WEBXML"
        fi
        ;;
    *)
        echo "usage: setup.sh <apache|nginx|tomcat> <vuln|hardened>" >&2
        exit 2
        ;;
esac
