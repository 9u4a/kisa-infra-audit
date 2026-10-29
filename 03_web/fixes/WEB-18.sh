# WEB-18 (상) 웹 서비스 WebDAV 비활성화 — 조치 [fix: auto]
# Debian/Ubuntu 레이아웃(mods-enabled/*.load·*.conf 심볼릭 링크)은 a2dismod 와 같은 방식으로 dav 모듈의
# 링크(.load 와 같은 이름의 .conf)를 제거한다(1.3.3, F-R4). 링크는 tar 로 백업되어(fix_backup_remove_path)
# 원복 시 링크 그대로 되살아난다. 예전에는 링크 대상 파일의 LoadModule 만 sed -i 로 주석 처리해 ① 링크가
# 일반 파일로 바뀌고 ② dav_fs.conf 의 DAVLockDB(대문자)가 남아 문법 검사 실패 → 원복으로 끝났다.
run_fix() {
    detect_web_engines
    applied=""

    case " $WEB_ENGINES " in *" apache "*)
        conf=$(apache_conf_path)
        files="$conf $(apache_extra_confs)"
        dav_re='^[^#]*LoadModule[[:space:]]+dav(_fs|_lock)?_module'
        # 1) Debian mods-enabled: a2dismod 방식(링크 제거)
        dismod=""
        for f in $files; do
            case "$f" in */mods-enabled/*.load) ;; *) continue ;; esac
            [ -f "$f" ] || continue
            grep -qE "$dav_re" "$f" 2>/dev/null || continue
            for p in "$f" "${f%.load}.conf"; do
                [ -e "$p" ] || [ -L "$p" ] || continue
                fix_backup_remove_path "$p"
                dismod="$dismod ${p##*/}"
            done
        done
        [ -n "$dismod" ] && applied="$applied apache(mods-enabled 링크 제거:$dismod)"

        # 2) 그 밖의 설정 파일: LoadModule 주석 처리. 모듈을 끄면 다른 파일에 남은 Dav/DAVLockDB/DavMinTimeout 등이
        #    "Invalid command" 가 되어 Apache 가 기동에 실패하므로, 로드되는 모든 설정의 Dav* 지시어도 함께 주석 처리한다
        #    (대소문자 무시 - Debian 은 DAVLockDB). 모듈이 남아 있지 않으면 Dav On 만 Off 로 바꾼다.
        files="$conf $(apache_extra_confs)"
        dav_loaded=""
        [ -n "$dismod" ] && dav_loaded=1
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE "$dav_re" "$f" 2>/dev/null && dav_loaded=1
        done
        dav_dir_re='^[[:space:]]*[Dd][Aa][Vv][A-Za-z]*[[:space:]]'
        for f in $files; do
            [ -f "$f" ] || continue
            if [ -n "$dav_loaded" ]; then
                grep -qE "^[[:space:]]*LoadModule[[:space:]]+dav(_fs|_lock)?_module|$dav_dir_re" "$f" 2>/dev/null || continue
                fix_backup "$f"
                fix_sed_inplace "$f" -E 's/^([[:space:]]*)(LoadModule[[:space:]]+dav(_fs|_lock)?_module.*)/\1#\2/; s/^([[:space:]]*)([Dd][Aa][Vv][A-Za-z]*[[:space:]].*)/\1#\2/'
            else
                grep -qiE '^[^#]*Dav[[:space:]]+On' "$f" 2>/dev/null || continue
                fix_backup "$f"
                fix_sed_inplace "$f" -E 's/^([[:space:]]*[Dd][Aa][Vv][[:space:]]+)[Oo][Nn]/\1Off/'
            fi
            applied="$applied apache($f)"
        done
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        conf=$(nginx_conf_path)
        files="$conf $(nginx_extra_confs)"
        for f in $files; do
            [ -f "$f" ] || continue
            grep -qE '^[^#]*dav_methods' "$f" 2>/dev/null || continue
            fix_backup "$f"
            fix_sed_inplace "$f" -E 's/^([[:space:]]*)(dav_methods.*)/\1#\2/'
            applied="$applied nginx($f)"
        done
    esac

    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"
        FIX_DETAIL="WebDAV 설정을 비활성화함:$applied"
        FIX_EVIDENCE="$applied"
    else
        FIX_STATUS="NA"
        FIX_DETAIL="WebDAV 가 활성화된 엔진이 없음(이미 정상)"
        FIX_EVIDENCE=""
    fi
}
