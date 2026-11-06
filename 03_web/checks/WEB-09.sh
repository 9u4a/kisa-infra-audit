# WEB-09 (상) 웹 서비스 프로세스 권한 제한
# 판단 기준(가이드 원문): 양호 = 관리자 권한이 아닌 별도 최소 권한 계정으로 구동
#                        취약 = 관리자(root) 권한 계정으로 구동
# 자동화 범위: /proc 기반으로 직접 프로세스를 조회한다(ps/pgrep 미설치 최소 컨테이너 대응).
# Apache/Nginx 는 마스터(권한 있는 포트 바인딩용)는 root 로 남고 실제 요청을 처리하는 worker
# 자식 프로세스만 권한을 낮추는 것이 정상 설계이므로, 인스턴스(최상위 마스터와 그 자식들)마다 non-root 프로세스가
# 하나라도 있으면 그 인스턴스는 GOOD, 전부 root 인 인스턴스가 하나라도 있으면 VULN(1.5.0 A23).
# Tomcat 은 아무 java 프로세스가 아니라 org.apache.catalina.startup.Bootstrap 을 실행하는 java 만 본다(WEB-R10).

run_check() {
    detect_web_engines
    violations=""; errors=""; manuals=""; evidence=""; checked=0

    # judge_pids <라벨> <PID 목록> <tree|each>
    #   tree: 같은 이름의 부모(마스터)를 따라 올라가 인스턴스(최상위 마스터)별로 묶고, 인스턴스마다 비 root 프로세스(worker)가
    #         하나라도 있어야 양호(Apache/Nginx - 마스터만 root 인 것은 정상 설계).
    #   each: 프로세스 하나가 곧 인스턴스(Tomcat Bootstrap java) - root 로 뜬 것이 하나라도 있으면 취약.
    # 1.5.0 A23: 예전에는 엔진 전체에서 비 root 프로세스가 하나만 있어도 GOOD 이라, 인스턴스 하나가 root 전용으로 떠 있어도 놓쳤다.
    judge_pids() {
        _label=$1; _mode=$3
        _pids=$(printf '%s\n' $2 | grep -v '^$')
        if [ -z "$_pids" ]; then
            evidence="$evidence
[$_label] 프로세스를 찾지 못함(/proc 기준)"
            manuals="$manuals $_label(실행 중인 프로세스를 찾지 못해 실행 계정 확인 불가)"
            return
        fi
        _rows=""
        for _pid in $_pids; do
            _uid=$(proc_uid "$_pid")
            # 목록을 만든 뒤 끝난 프로세스(reload 직후 종료되는 이전 worker 등)는 건너뛴다 - 남아 있는데 못 읽은 것만 확인 불가
            [ -n "$_uid" ] || [ -e "/proc/$_pid/status" ] || continue
            _top=$_pid
            if [ "$_mode" = tree ]; then
                _n=0
                while [ "$_n" -lt 16 ]; do
                    _pp=$(awk '/^PPid:/ { print $2; exit }' "/proc/$_top/status" 2>/dev/null)
                    case " $(printf '%s ' $_pids)" in *" $_pp "*) _top=$_pp ;; *) break ;; esac
                    _n=$((_n + 1))
                done
            fi
            _rows="$_rows$_top $_pid ${_uid:-?}
"
        done
        if [ -z "$_rows" ]; then
            manuals="$manuals $_label(프로세스가 확인 도중 모두 종료되어 실행 계정 확인 불가)"
            return
        fi
        _res=$(printf '%s' "$_rows" | awk '
            NF == 3 { if (!($1 in seen)) { seen[$1] = 1; ord[++n] = $1 } d[$1] = d[$1] " pid=" $2 ",uid=" $3; if ($3 != "0" && $3 != "?") nr[$1] = 1; if ($3 == "?") unk[$1] = 1 }
            END { for (i = 1; i <= n; i++) { t = ord[i]; print (nr[t] ? "OK" : (unk[t] ? "UNK" : "ROOT")) "\t" t "\t" d[t] } }')
        evidence="$evidence
[$_label] 인스턴스(최상위 프로세스)별 실행 계정:
$(printf '%s\n' "$_res" | awk -F '\t' '{ print "  instance " $2 ":" $3 " => " $1 }')"
        _root=$(printf '%s\n' "$_res" | awk -F '\t' '$1 == "ROOT" { printf " %s", $2 }')
        _unk=$(printf '%s\n' "$_res" | awk -F '\t' '$1 == "UNK" { printf " %s", $2 }')
        [ -n "$_root" ] && violations="$violations $_label(root 로만 구동되는 인스턴스 pid:$_root)"
        [ -n "$_unk" ] && errors="$errors $_label(실행 계정을 읽지 못한 인스턴스 pid:$_unk)"
    }

    case " $WEB_ENGINES " in *" apache "*)
        checked=1
        judge_pids "Apache" "$(proc_pids_by_comm httpd) $(proc_pids_by_comm apache2)" tree
    esac
    case " $WEB_ENGINES " in *" nginx "*)
        checked=1
        judge_pids "Nginx" "$(proc_pids_by_comm nginx)" tree
    esac
    case " $WEB_ENGINES " in *" tomcat "*)
        checked=1
        judge_pids "Tomcat" "$(tomcat_pids)" each
    esac

    web_finish "관리자(root) 권한으로만 구동 중인 웹 프로세스 존재" "웹 서비스 프로세스가 관리자 권한이 아닌 계정으로 구동됨" \
        "프로세스를 찾지 못해 실행 계정을 확인할 수 없음(수동 확인 필요)"
}
