# U-01 (상) root 계정 원격 접속 제한 — 조치
# 가이드 조치 방법: sshd_config 에 PermitRootLogin no 설정
# 운영 안전(1.2.2):
#  - root 외 관리자 수단(sudo/wheel/admin 그룹 구성원, sudoers 개별 지정)이 없으면 바꾸지 않는다 -
#    다음 sshd 재시작 때 원격 관리 경로가 모두 막히는 "지연 lockout" 방지.
#  - sshd 는 같은 키워드의 처음 값을 쓰므로 sshd_config 맨 앞(Include 보다 위)에 넣는다. 예전처럼
#    기존 줄만 바꾸거나 끝에 덧붙이면 sshd_config.d 드롭인 값이 우선하거나, 파일이 Match 블록으로
#    끝날 때 그 블록 안에만 적용됐다. 또 sed 일괄 치환이 Match 블록의 비상용 예외까지 바꿨다.
#  - Match 블록의 예외는 관리자가 의도한 비상 접근일 수 있어 건드리지 않고 결과에 알린다.
#  - sshd -t 문법 검사를 통과해야만 유지한다(실패 시 FIX_STATUS=ERROR → fix.sh 가 원복).
#  - sshd 재시작/reload 는 하지 않는다(현재 관리 세션 보호).
run_fix() {
    case "$OS_FAMILY" in
        rhel|debian|suse) : ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="환경(${OS_FAMILY})에 대한 자동 조치 미구현"; FIX_EVIDENCE=""; return ;;
    esac
    sshd_cfg="/etc/ssh/sshd_config"
    if [ ! -f "$sshd_cfg" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="$sshd_cfg 파일이 없음"; FIX_EVIDENCE=""
        return
    fi

    admins=$(awk -F: '($1 == "sudo" || $1 == "wheel" || $1 == "admin") && $4 != "" { print $1 ":" $4 }' /etc/group 2>/dev/null)
    sudoers_users=$(cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null | \
        grep -E '^[[:space:]]*[a-z_][a-z0-9_.-]*[[:space:]]+[^=]*=' | awk '{ print $1 }' | \
        grep -vE '^(root|Defaults|User_Alias|Runas_Alias|Host_Alias|Cmnd_Alias)$' | sort -u | tr '\n' ' ')
    if [ -z "$admins" ] && [ -z "$sudoers_users" ]; then
        FIX_STATUS="ERROR"
        FIX_DETAIL="root 외 관리자 계정(sudo/wheel/admin 그룹 구성원 또는 sudoers 지정)이 없어 변경하지 않음 - root 원격 접속을 막으면 sshd 재시작 후 원격 관리가 불가능해질 수 있음. 관리자 계정을 먼저 만든 뒤 다시 실행할 것"
        FIX_EVIDENCE=""
        return
    fi

    base_ok=1
    if command -v sshd >/dev/null 2>&1; then sshd -t -f "$sshd_cfg" >/dev/null 2>&1 || base_ok=0; else base_ok=0; fi

    fix_backup "$sshd_cfg"
    { printf '# KISA U-01: root 원격 접속 제한 (sshd 는 처음 나온 값을 적용하므로 맨 앞에 둠)\nPermitRootLogin no\n'
      cat "$sshd_cfg"; } > "$sshd_cfg.kisa_tmp" && fix_write_back "$sshd_cfg.kisa_tmp" "$sshd_cfg"

    if [ "$base_ok" -eq 1 ] && ! out=$(sshd -t -f "$sshd_cfg" 2>&1); then
        FIX_STATUS="ERROR"; FIX_DETAIL="변경 후 sshd -t 문법 검사 실패 - 원복함: $out"; FIX_EVIDENCE="$out"
        return
    fi
    sshd_effective_value PermitRootLogin
    if [ "$(printf '%s' "$SSHD_VALUE" | tr '[:upper:]' '[:lower:]')" != "no" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="변경 후에도 적용 값이 no 가 아님(${SSHD_VALUE:-확인 불가}, $SSHD_VALUE_SOURCE) - 원복함"; FIX_EVIDENCE=""
        return
    fi

    note=""
    overrides=$(sshd_match_overrides PermitRootLogin | grep -viE 'PermitRootLogin[[:space:]]+no([[:space:]]|$)')
    [ -n "$overrides" ] && note="$note / Match 블록 예외는 유지함(비상 접근 여부 확인 필요): $overrides"
    [ -n "${SSH_CONNECTION:-}" ] && [ -z "${SUDO_USER:-}" ] && \
        note="$note / 주의: 현재 세션이 root 로 직접 SSH 접속한 것으로 보임 - sshd 재시작 후에는 관리자 계정으로 접속해 sudo 를 쓸 것"
    [ "$base_ok" -eq 0 ] && note="$note / sshd -t 검사를 할 수 없어(명령 없음 또는 기존 설정 자체가 검사 실패) 문법 검증 생략"

    FIX_STATUS="APPLIED"
    FIX_DETAIL="$sshd_cfg 맨 앞에 PermitRootLogin no 설정함 (sshd 재시작/reload 후 적용 — 현재 세션 영향 없음, 대체 관리자: ${admins:-}${sudoers_users:+ sudoers:$sudoers_users})$note"
    FIX_EVIDENCE="$(sshd_global_lines | grep -iE '^PermitRootLogin[[:space:]]')"
}
