# WEB-17 (중) 웹 서비스 가상 디렉로리 삭제 — 조치 [fix: param]
# 값: aliases=없앨 가상 디렉터리 URL 경로(쉼표 구분, 예: /manual, /virtual/) - 진단 증적의 Alias/alias 목록 중 업무상 필요 없는 것
# 변경: Apache: 그 URL 의 Alias/ScriptAlias/AliasMatch 줄을 주석 처리 / Nginx: 그 URL 의 location 블록(alias 가 있는 것)을 통째로 주석 처리
#       - 가리키던 디렉터리·파일은 지우지 않음
# 영향: 다음 reload·재시작부터 지정 URL 이 404(또는 문서 루트의 같은 경로)로 응답 — 그 경로를 쓰던 링크·앱 기능이 끊김
# 가이드 조치 방법: 불필요한 가상 디렉터리 삭제. 필요 여부는 업무 판단이라 진단은 MANUAL·조치 manual 이었다 - 1.7.0 값 지정 조치로
# 운영자가 고른 URL 만 없앤다. reload 는 하지 않는다(진입점이 문법 검사, 실패 시 원복).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): / 로 시작·공백 없음·중복 없음, 그리고 Apache/Nginx 설정에서 그 URL 의 가상 디렉터리를
# 실제로 찾음. Tomcat <Context path> 는 XML 요소 삭제라(여러 줄·하위 요소) 자동으로 하지 않는다(값에 Tomcat 만 해당하면 거부, 수동 조치).
run_fix() {
    urls=$(fix_param aliases)
    if [ -z "$urls" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 WEB-17.aliases 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    detect_web_engines
    afiles=""; nfiles=""
    case " $WEB_ENGINES " in *" apache "*) afiles="$(apache_conf_path) $(apache_extra_confs)" ;; esac
    case " $WEB_ENGINES " in *" nginx "*) nfiles="$(nginx_conf_path) $(nginx_extra_confs)" ;; esac

    # _web17_apache_lines <파일> <URL> -> 그 URL 을 첫 인자로 갖는 Alias 류 줄 번호
    _web17_apache_lines() {
        awk -v u="$2" '{ t = $0; sub(/^[ \t]+/, "", t); if (t ~ /^#/) next
            n = split(t, a, /[ \t]+/); d = tolower(a[1]); g = a[2]; gsub(/"/, "", g)
            if ((d == "alias" || d == "scriptalias" || d == "aliasmatch" || d == "scriptaliasmatch") && g == u) print NR }' "$1" 2>/dev/null
    }
    # _web17_nginx_blocks <파일> <URL> [apply] -> URL 이 마지막 인자인 location 블록 중 alias 가 든 것의 수(apply 면 주석 처리한 파일 내용)
    _web17_nginx_blocks() {
        awk -v u="$2" -v mode="${3:-count}" '
            function flush(   i) { for (i = 1; i <= nb; i++) print (hit ? "# KISA WEB-17 " : "") buf[i]; nb = 0 }
            {
                t = $0; sub(/#.*/, "", t)
                if (!inb && match(t, /^[ \t]*location[ \t]+[^{]*\{/)) {
                    h = substr(t, RSTART, RLENGTH); sub(/\{$/, "", h); sub(/[ \t]+$/, "", h); n = split(h, a, /[ \t]+/)
                    if (a[n] == u) { inb = 1; depth = 0; nb = 0; hit = 0 }
                }
                if (inb) {
                    buf[++nb] = $0
                    if (t ~ /(^|[ \t;{])alias[ \t]/) hit = 1
                    o = gsub(/\{/, "{", t); c = gsub(/\}/, "}", t); depth += o - c
                    if (depth <= 0) { found += hit; if (mode == "apply") flush(); inb = 0 }
                    next
                }
                if (mode == "apply") print
            }
            END { if (inb && mode == "apply") flush(); if (mode != "apply") print found + 0 }' "$1" 2>/dev/null
    }

    errs=""; seen=" "
    while IFS= read -r u; do
        [ -n "$u" ] || continue
        case "$seen" in *" $u "*) errs="$errs / $u: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$u "
        case "$u" in /*) ;; *) errs="$errs / $u: / 로 시작하는 URL 경로가 아님"; continue ;; esac
        case "$u" in *[[:space:]]*) errs="$errs / $u: 공백이 든 경로"; continue ;; esac
        n=0
        for f in $afiles; do [ -f "$f" ] && n=$((n + $(_web17_apache_lines "$f" "$u" | grep -c .))); done
        for f in $nfiles; do [ -f "$f" ] && n=$((n + $(_web17_nginx_blocks "$f" "$u"))); done
        [ "$n" -gt 0 ] || errs="$errs / $u: Apache Alias·Nginx alias location 에서 찾지 못함(Tomcat Context 는 수동 조치)"
    done <<EOF
$urls
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    applied=""
    for f in $afiles; do
        [ -f "$f" ] || continue
        expr=""
        for u in $seen; do
            for ln in $(_web17_apache_lines "$f" "$u"); do expr="$expr${ln}s/^/# KISA WEB-17 /;"; done
        done
        [ -n "$expr" ] || continue
        fix_backup "$f"
        fix_sed_inplace "$f" "$expr" && applied="$applied apache($f)"
    done
    for f in $nfiles; do
        [ -f "$f" ] || continue
        changed=0
        for u in $seen; do
            [ "$(_web17_nginx_blocks "$f" "$u")" -gt 0 ] || continue
            [ "$changed" -eq 1 ] || fix_backup "$f"
            _web17_nginx_blocks "$f" "$u" apply > "$f.kisa_tmp" && fix_write_back "$f.kisa_tmp" "$f" && changed=1
        done
        [ "$changed" -eq 1 ] && applied="$applied nginx($f)"
    done
    if [ -n "$applied" ]; then
        FIX_STATUS="APPLIED"; FIX_DETAIL="지정 가상 디렉터리($(printf '%s' "$seen" | sed 's/^ //; s/ $//; s/ /, /g'))를 주석 처리함(다음 reload·재시작부터):$applied"
        FIX_EVIDENCE=$(grep -h 'KISA WEB-17' $afiles $nfiles 2>/dev/null | head -n 20)
    else
        FIX_STATUS="ERROR"; FIX_DETAIL="지정 가상 디렉터리를 주석 처리하지 못함"; FIX_EVIDENCE=""
    fi
}
