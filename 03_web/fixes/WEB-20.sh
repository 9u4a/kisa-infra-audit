# WEB-20 (상) SSL/TLS 활성화 — 조치 [fix: param]
# 값: cert=PEM 서버 인증서 파일 절대 경로(체인 포함 가능) - 운영자가 발급받아 서버에 둔 것
# 값: key=PEM 개인 키 파일 절대 경로(암호 없는 키 - 웹 서버가 시작할 때 읽을 수 있어야 함)
# 변경: Apache: mod_ssl 로드(주석 LoadModule 해제 또는 Debian mods-enabled 링크) + Listen 443(없을 때) + 메인 설정 끝에
#       <VirtualHost _default_:443> SSLEngine on·인증서·키 / Nginx: http 블록이 include 하는 conf.d 에 listen 443 ssl 서버 블록 파일
# 영향: 다음 reload·재시작부터 443 포트로 HTTPS 를 받음 — 같은 포트를 쓰는 다른 프로그램이 있으면 웹 서버가 기동하지 못함(문법 검사로는 못 잡음)
# 가이드 조치 방법: SSL/TLS 활성화(인증서 설치·설정). 신뢰할 수 있는 인증서를 스크립트가 발급할 수 없어 manual 이었다 - 1.7.0 값 지정
# 조치로 운영자가 준비한 인증서·키 경로를 정책 값으로 받는다. reload 는 하지 않는다(설정만 - 진입점이 문법 검사, 실패 시 원복).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 절대 경로·일반 파일·PEM 형식(인증서/개인 키 머리줄), openssl 이 있으면 인증서 파싱·
# 만료 아님·키와 인증서 공개키 일치까지. Tomcat 은 진단 대상이 아니다(가이드 대상 Apache·Nginx·IIS·WebtoB).
run_fix() {
    cert=$(fix_param cert); key=$(fix_param key)
    if [ -z "$cert" ] && [ -z "$key" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 WEB-20.cert·key 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    errs=""
    [ "$(printf '%s\n' "$cert" | grep -c .)" = 1 ] || errs="$errs / cert 는 파일 하나여야 함"
    [ "$(printf '%s\n' "$key" | grep -c .)" = 1 ] || errs="$errs / key 는 파일 하나여야 함"
    for f in "$cert" "$key"; do
        case "$f" in /*) ;; *) errs="$errs / $f: 절대 경로가 아님"; continue ;; esac
        if [ -L "$f" ] || [ ! -f "$f" ] || [ ! -r "$f" ]; then errs="$errs / $f: 읽을 수 있는 일반 파일이 아님"; fi
    done
    if [ -z "$errs" ]; then
        grep -q -- '-----BEGIN CERTIFICATE-----' "$cert" || errs="$errs / $cert: PEM 인증서가 아님"
        grep -qE -- '-----BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY-----' "$key" || errs="$errs / $key: PEM 개인 키가 아님"
        grep -q -- '-----BEGIN ENCRYPTED PRIVATE KEY-----' "$key" && errs="$errs / $key: 암호가 걸린 키 - 웹 서버가 무인 기동할 수 없음"
    fi
    if [ -z "$errs" ] && command -v openssl >/dev/null 2>&1; then
        openssl x509 -noout -in "$cert" >/dev/null 2>&1 || errs="$errs / $cert: 인증서를 읽지 못함"
        openssl x509 -noout -checkend 0 -in "$cert" >/dev/null 2>&1 || errs="$errs / $cert: 만료된 인증서"
        cp_=$(openssl x509 -noout -pubkey -in "$cert" 2>/dev/null); kp_=$(openssl pkey -in "$key" -pubout 2>/dev/null)
        [ -n "$kp_" ] && [ "$cp_" = "$kp_" ] || errs="$errs / 개인 키가 인증서와 짝이 아님"
    fi
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    detect_web_engines
    applied=""; failed=""
    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        loaded=0; listen=0
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qiE '^[^#]*LoadModule[[:space:]]+ssl_module' "$f" && loaded=1
            grep -qiE '^[^#]*Listen[[:space:]]+([^[:space:]]*:)?443([[:space:]]|$)' "$f" && listen=1
        done
        if [ "$loaded" -eq 0 ]; then
            if grep -qiE '^[[:space:]]*#[[:space:]]*LoadModule[[:space:]]+ssl_module' "$conf"; then
                fix_backup "$conf"
                fix_sed_inplace "$conf" -E 's/^[[:space:]]*#[[:space:]]*(LoadModule[[:space:]]+ssl_module)/\1/'
                loaded=1
            elif [ -f /etc/apache2/mods-available/ssl.load ] && [ -d /etc/apache2/mods-enabled ]; then
                # Debian(a2enmod ssl 과 같은 링크). ssl.conf 의 SSLSessionCache shmcb 때문에 socache_shmcb 도 켠다
                for m in ssl.load ssl.conf socache_shmcb.load; do
                    [ -f "/etc/apache2/mods-available/$m" ] || continue
                    [ -e "/etc/apache2/mods-enabled/$m" ] && continue
                    fix_backup "/etc/apache2/mods-enabled/$m"
                    ln -s "../mods-available/$m" "/etc/apache2/mods-enabled/$m"
                done
                loaded=1
                # ports.conf 는 <IfModule ssl_module> Listen 443 을 이미 갖고 있다
                grep -qiE '^[^#]*Listen[[:space:]]+443' /etc/apache2/ports.conf 2>/dev/null && listen=1
            fi
        fi
        if [ "$loaded" -eq 0 ]; then
            failed="$failed apache(mod_ssl 모듈을 찾지 못함 - mod_ssl 설치 후 다시)"
        else
            fix_backup "$conf"
            {
                printf '\n# KISA WEB-20 (1.7.0 값 지정 조치) - SSL/TLS 활성화\n'
                [ "$listen" -eq 0 ] && printf 'Listen 443\n'
                printf '<VirtualHost _default_:443>\n    SSLEngine on\n    SSLCertificateFile "%s"\n    SSLCertificateKeyFile "%s"\n</VirtualHost>\n' "$cert" "$key"
            } >> "$conf"
            applied="$applied apache($conf)"
        fi
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        # http 블록 안의 "include <폴더>/*.conf;" 폴더(공식 이미지·배포판 기본 conf.d)에 새 파일로 둔다
        incdir=$(awk '{ sub(/#.*/, "") } /^[[:space:]]*http[[:space:]]*\{/ { h = 1 } h && match($0, /include[[:space:]]+[^;]*\/\*\.conf;/) {
                p = substr($0, RSTART, RLENGTH); sub(/^include[[:space:]]+/, "", p); sub(/\/\*\.conf;$/, "", p); print p; exit }' "$conf" 2>/dev/null)
        case "$incdir" in /*) ;; ?*) incdir="$(dirname "$conf")/$incdir" ;; esac
        root=$(for f in $conf $(nginx_extra_confs); do sed -n 's/^[^#]*[[:space:]]root[[:space:]]\{1,\}\([^;]*\);.*/\1/p' "$f" 2>/dev/null; done | head -n 1)
        newf="$incdir/kisa-web20-ssl.conf"
        if [ -z "$incdir" ] || [ ! -d "$incdir" ]; then
            failed="$failed nginx(http 블록의 include 폴더(*.conf)를 찾지 못함 - 수동 설정)"
        elif [ -e "$newf" ]; then
            failed="$failed nginx($newf 가 이미 있음)"
        else
            fix_backup "$newf"
            printf '# KISA WEB-20 (1.7.0 값 지정 조치) - SSL/TLS 활성화\nserver {\n    listen 443 ssl;\n    ssl_certificate %s;\n    ssl_certificate_key %s;\n%s}\n' \
                "$cert" "$key" "${root:+    root $root;
}" > "$newf"
            chmod 644 "$newf"
            applied="$applied nginx($newf)"
        fi
    esac

    FIX_EVIDENCE="cert=$cert key=$key"
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="SSL/TLS 활성화 실패:$failed${applied:+ (적용된 부분:$applied - 원복됨)}"
    elif [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="SSL/TLS 설정을 추가함(다음 reload·재시작부터 443 HTTPS):$applied"
    else
        FIX_STATUS="NA"; FIX_DETAIL="SSL/TLS 대상 엔진(Apache·Nginx)이 없음"
    fi
}
