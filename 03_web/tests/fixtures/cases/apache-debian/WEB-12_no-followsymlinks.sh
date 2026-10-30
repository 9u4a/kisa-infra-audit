#!/bin/sh
# shellcheck disable=SC2034  # 공통 경로 변수(CONF/VHOST/DEF/SX/WX/UX/CX)를 케이스마다 다 쓰지는 않음
# GOOD: 로드되는 모든 설정의 Options 에서 FollowSymLinks 제거(apache2.conf 의 / 와 /var/www, mods-enabled/alias.conf 의 icons 폴더)
. 03_web/tests/fixtures/cases/case_lib.sh
CONF=/etc/apache2/apache2.conf
sed -i -e 's|^\([[:space:]]*\)Options FollowSymLinks$|\1Options None|' -e 's|^\([[:space:]]*\)Options Indexes FollowSymLinks$|\1Options Indexes|' "$CONF"
# Debian 기본 alias.conf 의 /usr/share/apache2/icons 에도 "Options FollowSymlinks" 가 있다(대소문자 섞임)
sed -i 's|^\([[:space:]]*\)Options FollowSymlinks MultiViews$|\1Options MultiViews|; s|^\([[:space:]]*\)Options FollowSymlinks$|\1Options None|' /etc/apache2/mods-available/alias.conf
# -R: *-enabled 안의 심볼릭 링크도 따라가 확인(-r 은 링크를 건너뛴다)
assert_not grep -RqiE '^[^#]*Options[^#]*([[:space:]]|\+)(FollowSymLinks|All)([[:space:]]|$)' /etc/apache2/apache2.conf /etc/apache2/sites-enabled/ /etc/apache2/conf-enabled/ /etc/apache2/mods-enabled/
assert apache2ctl -t
