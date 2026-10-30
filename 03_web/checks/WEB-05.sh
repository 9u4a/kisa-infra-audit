# WEB-05 (상) 지정하지 않은 CGI/ISAPI 실행 제한
# 판단 기준(가이드 원문): 양호 = CGI 미사용 또는 실행 가능 디렉터리를 제한한 경우
#                        취약 = CGI 사용하며 제한하지 않은 경우
# 1.4.0(커버리지 검수 WEB-C1): 예전에는 CGI 가 켜져 있으면 무조건 MANUAL 이라 "제한하지 않음(VULN)"을 판정하지 못했다.
# 가이드 조치 예시를 기준으로 "실행 디렉터리 제한" 여부를 설정에서 판정한다(가이드 원문 해석 - deviation 참고).
#   Apache : cgi/cgid 모듈 미로드 → GOOD. 로드 시 ScriptAlias 대상 <Directory> 밖에서 ExecCGI(또는 All)가 켜져 있으면
#            (서버 전역·문서 루트 등 지정하지 않은 디렉터리에서 CGI 실행 가능) VULN, 아니면 ScriptAlias 디렉터리로
#            제한된 것으로 GOOD. (가이드 Step 2 "모든 디렉터리의 Options 에서 ExecCGI 제거", ※ 필요한 디렉터리만 제한적 허용)
#   Nginx  : fastcgi_pass 가 경로가 지정된 location(접두 경로 또는 ^/경로/ 로 고정된 정규식) 안에만 있으면 GOOD,
#            server/http 수준·확장자만으로 매칭하는 정규식 location(가이드 예시 "location ~ \.cgi$")·"/"·이름 있는
#            location(@) 안에 있으면 어느 디렉터리의 스크립트든 실행되므로 VULN.
#   Tomcat : cgi servlet-mapping 활성 시 CGIServlet 의 cgiPathPrefix(스크립트 탐색 시작 경로)가 미지정(기본
#            WEB-INF/cgi)이거나 WEB-INF/ 아래면 웹으로 올릴 수 없는 디렉터리로 제한된 것으로 GOOD, 그 밖(웹 경로)이면 VULN.
# Tomcat 은 XML 주석을 먼저 지운 뒤 찾는다 - 기본 web.xml 의 주석 속 예시를 활성으로 보지 않는다(진단 검수 WEB-R11).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        if web_load_conf apache; then
            cgi_on=""
            for f in $WEB_FILES; do
                hit=$(grep -niE '^[^#]*LoadModule[[:space:]]+cgid?_module' "$f" 2>/dev/null)
                [ -n "$hit" ] && cgi_on="$cgi_on
$f: $hit"
            done
            evidence="$evidence
[Apache] cgi 모듈 로드: ${cgi_on:-미사용}"
            if [ -n "$cgi_on" ]; then
                # 1차: ScriptAlias 대상 폴더 수집, 2차: 그 폴더의 <Directory> 밖에서 ExecCGI/All 이 켜진 Options 줄
                # shellcheck disable=SC2086
                sa_dirs=$(awk '{ t = $0; sub(/\r$/, "", t); sub(/^[ \t]+/, "", t); n = split(t, a, /[ \t]+/)
                                 if (tolower(a[1]) == "scriptalias" && n >= 3) { d = a[3]; gsub(/"/, "", d); sub(/\/+$/, "", d); print d } }' $WEB_FILES 2>/dev/null)
                # shellcheck disable=SC2086
                open=$(SA_DIRS=$sa_dirs awk '
                    BEGIN { m = split(ENVIRON["SA_DIRS"], s, "\n"); for (i = 1; i <= m; i++) if (s[i] != "") sa[s[i]] = 1 }
                    { t = $0; sub(/\r$/, "", t); sub(/^[ \t]+/, "", t); n = split(t, a, /[ \t]+/); k = tolower(a[1]) }
                    k ~ /^<directory$/ { d = a[2]; gsub(/[">]/, "", d); sub(/\/+$/, "", d); cur = d; next }
                    k ~ /^<\/directory>?$/ { cur = ""; next }
                    k == "options" {
                        for (i = 2; i <= n; i++) { w = tolower(a[i]); sub(/^\+/, "", w)
                            if (w == "execcgi" || w == "all") { if (!(cur != "" && (cur in sa))) print FILENAME ":" FNR ": " t (cur == "" ? " (디렉터리 지정 없음)" : " (<Directory " cur ">)"); break } }
                    }' $WEB_FILES 2>/dev/null)
                evidence="$evidence
[Apache] ScriptAlias 디렉터리 밖에서 ExecCGI/All 허용: ${open:-없음(ScriptAlias 디렉터리로 제한)}"
                [ -n "$open" ] && violations="$violations apache(지정하지 않은 디렉터리에서 CGI 실행 허용)"
            fi
        fi
    esac

    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        if web_load_conf nginx; then
            fcgi=""
            for f in $WEB_FILES; do
                # 주석 제거 후 { } ; 단위로 잘라 location 블록 스택을 따라가며 fastcgi_pass 의 위치를 판정한다.
                hit=$(awk '
                    { sub(/\r$/, ""); sub(/#.*/, ""); buf = buf " " $0 }
                    END {
                        s = buf; depth = 0
                        while (match(s, /[{};]/)) {
                            tok = substr(s, 1, RSTART - 1); c = substr(s, RSTART, 1); s = substr(s, RSTART + 1)
                            gsub(/^[ \t]+|[ \t]+$/, "", tok)
                            if (c == "{") { depth++; hdr[depth] = tok; continue }
                            if (c == "}") { if (depth > 0) depth--; continue }
                            if (tok !~ /^fastcgi_pass[ \t]/) continue
                            r = 0; where = "location 밖"
                            for (i = depth; i >= 1; i--) {
                                h = hdr[i]; if (h !~ /^location[ \t]/) continue
                                where = h; n = split(h, a, /[ \t]+/)
                                if (n >= 3) { m = a[2]; p = a[3] } else { m = ""; p = a[2] }
                                if (m == "~" || m == "~*") { if (p ~ /^\^\/[^\/]+\//) r = 1 }
                                else if (p ~ /^\// && p != "/") r = 1
                                if (r) break
                            }
                            print (r ? "R" : "U") "\t" where " { " tok " }"
                        } }' "$f" 2>/dev/null)
                [ -n "$hit" ] && fcgi="$fcgi
$(printf '%s\n' "$hit" | sed "s#^\([RU]\)	#\1	$f: #")"
            done
            shown=$(printf '%s' "$fcgi" | sed 's/^R	/[경로 제한] /; s/^U	/[제한 없음] /')
            evidence="$evidence
[Nginx] fastcgi_pass 사용: $(printf '%s' "${shown:-미사용}" | web_mask_url_secrets)"
            printf '%s\n' "$fcgi" | grep -q '^U	' && violations="$violations nginx(경로를 지정하지 않은 location 에서 fastcgi 실행)"
        fi
    esac

    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        if web_load_tomcat_conf web.xml; then
            flat=$(strip_xml_comments "$TC_FILE" | tr '\n\r\t' '   ')
            hit=$(printf '%s' "$flat" | \
                grep -oE '<servlet-mapping>[[:space:]]*<servlet-name>[[:space:]]*cgi[[:space:]]*</servlet-name>[[:space:]]*<url-pattern>[^<]*</url-pattern>')
            evidence="$evidence
[Tomcat] $TC_FILE cgi servlet-mapping: ${hit:-비활성/미설정}"
            if [ -n "$hit" ]; then
                pp=$(printf '%s' "$flat" | sed 's#</servlet>#&\n#g' | \
                    grep -E '<servlet-name>[[:space:]]*cgi[[:space:]]*</servlet-name>' | \
                    grep -oE '<param-name>[[:space:]]*cgiPathPrefix[[:space:]]*</param-name>[[:space:]]*<param-value>[^<]*</param-value>' | head -n 1)
                if [ -n "$pp" ]; then
                    prefix=$(printf '%s' "$pp" | sed -E 's#.*<param-value>([^<]*)</param-value>#\1#; s/^[[:space:]]+//; s/[[:space:]]+$//')
                else
                    prefix="WEB-INF/cgi"
                fi
                evidence="$evidence
[Tomcat] CGIServlet cgiPathPrefix: ${pp:+\"$prefix\"}${pp:-미지정(기본값 WEB-INF/cgi)}"
                case "$prefix" in
                    WEB-INF/?*|/WEB-INF/?*) : ;;
                    *) violations="$violations tomcat(cgiPathPrefix=\"$prefix\" - 웹 경로의 스크립트 실행 가능)" ;;
                esac
            fi
        fi
    esac

    web_finish "CGI 를 실행 디렉터리 제한 없이 사용하는 엔진" "CGI 를 사용하지 않거나 실행 가능한 디렉터리가 제한되어 있음"
}
