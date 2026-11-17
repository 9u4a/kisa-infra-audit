# U-07 (하) 불필요한 계정 제거 — 조치 [fix: param]
# 값: lock=잠글 계정 이름(쉼표 구분) - 진단 증적의 로그인 가능 계정 중 운영자가 불필요하다고 판단한 것
# 변경: 지정 계정 잠금(비밀번호 잠금 usermod -L, 계정 만료 usermod -e 1, 쉘 nologin) - 삭제하지 않음(홈·파일 보존)
# 영향: 지정 계정 로그인 즉시 차단 — 그 계정의 SSH 키 접속·su·cron 작업이 실패할 수 있음
# 가이드 조치 방법: 불필요한 계정 삭제(userdel). 자동 조치는 되돌릴 수 있도록 삭제 대신 잠근다(guide.json deviation).
# "불필요" 판단은 사람이 한다(진단은 MANUAL) - 정책 파일 [host:이름] 구역의 U-07.lock 값으로 받는다(1.7.0 값 지정 조치).
# 값은 모두 먼저 검증하고 하나라도 틀리면 아무것도 바꾸지 않는다: 없는 계정·UID 0·지금 조치를 실행한 계정·중복은 거부.
run_fix() {
    accts=$(fix_param lock)
    if [ -z "$accts" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 U-07.lock 이 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    case "${OS_FAMILY:-}" in
        rhel|debian|suse) ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="값 지정 조치는 Linux 전용(이 환경 ${OS_FAMILY:-알 수 없음}은 수동 조치)"; FIX_EVIDENCE=""; return ;;
    esac
    nologin=""
    for _n in /usr/sbin/nologin /sbin/nologin; do [ -x "$_n" ] && { nologin=$_n; break; }; done
    if [ -z "$nologin" ] || ! command -v usermod >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="nologin 또는 usermod 를 찾지 못해 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    errs=""; seen=" "
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        case "$seen" in *" $a "*) errs="$errs / $a: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$a "
        uid=$(awk -F: -v u="$a" '$1 == u { print $3; exit }' /etc/passwd)
        if [ -z "$uid" ]; then errs="$errs / $a: /etc/passwd 에 없는 계정"
        elif [ "$uid" = "0" ]; then errs="$errs / $a: UID 0(root 권한) 계정은 잠그지 않음"
        elif fix_is_operator_account "$a"; then errs="$errs / $a: 지금 조치를 실행한 계정"
        fi
    done <<EOF
$accts
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    fix_backup /etc/passwd
    [ -f /etc/shadow ] && fix_backup /etc/shadow
    failed=""; done_list=""
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        if usermod -L -e 1 -s "$nologin" "$a" >/dev/null 2>&1; then done_list="$done_list $a"; else failed="$failed $a"; fi
    done <<EOF
$accts
EOF
    # 확인: 쉘 nologin + 비밀번호 잠금(!) + 만료일 1
    bad=""
    for a in $done_list; do
        sh_now=$(awk -F: -v u="$a" '$1 == u { print $7; exit }' /etc/passwd)
        sp=$(awk -F: -v u="$a" '$1 == u { print substr($2, 1, 1) ":" $8; exit }' /etc/shadow 2>/dev/null)
        [ "$sh_now" = "$nologin" ] && [ "$sp" = "!:1" ] || bad="$bad $a"
    done
    ev=$(for a in $done_list; do awk -F: -v u="$a" '$1 == u { print $1 ":" $7 }' /etc/passwd; done)
    if [ -n "$failed" ] || [ -n "$bad" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="계정 잠금 실패:${failed}${bad:+ / 확인 실패:$bad}"; FIX_EVIDENCE="$ev"; return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="지정 계정을 잠금(비밀번호 잠금·만료·쉘 $nologin):$done_list"
    FIX_EVIDENCE="$ev"
}
