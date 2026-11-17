# U-08 (중) 관리자 그룹에 최소한의 계정 포함 — 조치 [fix: param]
# 값: remove=관리자 그룹에서 뺄 계정 이름(쉼표 구분) - 진단 증적의 GID 0·wheel·sudo·admin 구성원 중 운영자가 불필요하다고 판단한 것
# 변경: 지정 계정을 GID 0(root)·wheel·sudo·admin 그룹의 보조 구성원 목록에서 제거(gpasswd -d) - 계정 자체는 그대로
# 영향: 지정 계정의 관리자 권한(sudo·su 허용) 즉시 제거 — 그 계정으로 하던 관리 작업이 실패
# 가이드 조치 방법: 관리자 그룹(root)에 등록된 불필요한 계정 제거.
# "불필요" 판단은 사람이 한다(진단은 MANUAL) - 정책 파일 [host:이름] 구역의 U-08.remove 값으로 받는다(1.7.0 값 지정 조치).
# 기본 그룹(/etc/passwd 4번째 필드)이 GID 0 인 계정은 그룹 변경이 파일 소유 그룹까지 바꾸므로 자동으로 하지 않는다(값 검증에서 거부).
run_fix() {
    accts=$(fix_param remove)
    if [ -z "$accts" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 U-08.remove 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    case "${OS_FAMILY:-}" in
        rhel|debian|suse) ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="값 지정 조치는 Linux 전용(이 환경 ${OS_FAMILY:-알 수 없음}은 수동 조치)"; FIX_EVIDENCE=""; return ;;
    esac
    if ! command -v gpasswd >/dev/null 2>&1; then
        FIX_STATUS="ERROR"; FIX_DETAIL="gpasswd 를 찾지 못해 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    # admin_groups_of <계정> — 그 계정을 보조 구성원으로 가진 관리자 그룹 이름(공백 구분)
    admin_groups_of() {
        awk -F: -v u="$1" '($3 == 0 || $1 == "wheel" || $1 == "sudo" || $1 == "admin") {
            n = split($4, m, ","); for (i = 1; i <= n; i++) if (m[i] == u) { printf "%s ", $1; break } }' /etc/group
    }
    errs=""; seen=" "; plan=""
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        case "$seen" in *" $a "*) errs="$errs / $a: 값에 두 번 나옴"; continue ;; esac
        seen="$seen$a "
        pw=$(awk -F: -v u="$a" '$1 == u { print $3 ":" $4; exit }' /etc/passwd)
        groups=$(admin_groups_of "$a")
        if [ -z "$pw" ]; then errs="$errs / $a: /etc/passwd 에 없는 계정"
        elif [ "${pw%%:*}" = "0" ]; then errs="$errs / $a: UID 0(root) 계정은 대상 아님"
        elif fix_is_operator_account "$a"; then errs="$errs / $a: 지금 조치를 실행한 계정(관리 권한을 잃음)"
        elif [ "${pw#*:}" = "0" ]; then errs="$errs / $a: 기본 그룹이 GID 0 - 자동 변경하지 않음(수동 조치)"
        elif [ -z "$groups" ]; then errs="$errs / $a: 관리자 그룹(GID 0·wheel·sudo·admin)의 구성원이 아님"
        else plan="$plan$a:$groups
"
        fi
    done <<EOF
$accts
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    fix_backup /etc/group
    [ -f /etc/gshadow ] && fix_backup /etc/gshadow
    failed=""; done_list=""
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        a=${p%%:*}
        for g in ${p#*:}; do
            if gpasswd -d "$a" "$g" >/dev/null 2>&1; then done_list="$done_list $a($g)"; else failed="$failed $a($g)"; fi
        done
    done <<EOF
$plan
EOF
    left=""
    for a in $seen; do
        g=$(admin_groups_of "$a"); [ -n "$g" ] && left="$left $a($g)"
    done
    ev=$(awk -F: '$3 == 0 || $1 == "wheel" || $1 == "sudo" || $1 == "admin"' /etc/group)
    if [ -n "$failed" ] || [ -n "$left" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="관리자 그룹 구성원 제거 실패:${failed}${left:+ / 남아 있음:$left}"; FIX_EVIDENCE="$ev"; return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="관리자 그룹에서 지정 계정을 제거함:$done_list"
    FIX_EVIDENCE="$ev"
}
