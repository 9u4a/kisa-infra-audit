# U-33 (하) 숨겨진 파일 및 디렉토리 검색 및 제거 — 조치 [fix: param]
# 값: files=제거할 숨김 파일·디렉터리 절대 경로(쉼표 구분) - 진단 증적(홈 디렉터리 2단계까지의 숨김 항목) 중 의심스러운 것
# 변경: 지정 숨김 파일·디렉터리를 백업(tar)한 뒤 삭제 - 원복하면 백업에서 그대로 되살린다
# 영향: 지정 숨김 파일을 쓰던 프로그램(사용자 설정·자동 실행 스크립트 등)이 그 파일을 찾지 못함
# 가이드 조치 방법: 의심스러운 숨겨진 파일/디렉토리 삭제(rm). 의심 여부는 사람이 판단한다(진단은 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 절대 경로·이름이 "."으로 시작·존재·진단과 같은 범위(계정 홈 아래 2단계 이내,
# 시스템 디렉터리를 홈으로 쓰는 계정 제외)·진단이 통상 항목으로 빼는 이름(.ssh·.bashrc 등)이 아님·중복 없음.
run_fix() {
    files=$(fix_param files)
    if [ -z "$files" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 U-33.files 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    case "${OS_FAMILY:-}" in
        rhel|debian|suse) ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="값 지정 조치는 Linux 전용(이 환경 ${OS_FAMILY:-알 수 없음}은 수동 조치)"; FIX_EVIDENCE=""; return ;;
    esac
    homes=$(awk -F: '{ print $6 }' /etc/passwd | sort -u)
    errs=""; seen="
"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$seen" in *"
$f
"*) errs="$errs / $f: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$f
"
        case "$f" in /*) ;; *) errs="$errs / $f: 절대 경로가 아님"; continue ;; esac
        case "$f" in */|*/./*|*/../*|*/.|*/..) errs="$errs / $f: 경로 형식 오류(끝 / · . · ..)"; continue ;; esac
        b=$(basename "$f")
        case "$b" in .?*) ;; *) errs="$errs / $f: 숨김 파일 이름(.으로 시작)이 아님"; continue ;; esac
        case "$b" in
            .ssh|.cache|.config|.local|.bash_history|.bash_logout|.bashrc|.bash_profile|.profile|.viminfo|.lesshst|.gnupg|.mozilla|.Xauthority)
                errs="$errs / $f: 통상 항목(진단 제외 대상)이라 자동으로 지우지 않음"; continue ;;
        esac
        if [ ! -e "$f" ] && [ ! -L "$f" ]; then errs="$errs / $f: 없음"; continue; fi
        inhome=0
        for h in $homes; do
            case "$h" in /|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/dev|/proc|/sys|/run|/var/run|/nonexistent|"") continue ;; esac
            case "$f" in
                "$h"/*)
                    rest=${f#"$h"/}
                    case "$rest" in */*/*) ;; *) inhome=1 ;; esac ;;
            esac
        done
        [ "$inhome" -eq 1 ] || errs="$errs / $f: 계정 홈 디렉터리 아래 2단계 이내가 아님(진단 범위 밖)"
    done <<EOF
$files
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    # fix_backup_remove_path 는 tar 백업이 실패하면 삭제하지 않고 실행 전체를 멈춘다(F1)
    failed=""; n=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        fix_backup_remove_path "$f"
        if [ -e "$f" ] || [ -L "$f" ]; then failed="$failed $f"; else n=$((n + 1)); fi
    done <<EOF
$files
EOF
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="숨김 파일 삭제 실패:$failed"; FIX_EVIDENCE=""; return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="지정 숨김 파일·디렉터리 ${n}개를 백업 후 삭제함(원복 시 복원)"
    FIX_EVIDENCE="$files"
}
