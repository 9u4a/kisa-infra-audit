# U-23 (상) SUID, SGID, Sticky bit 설정 파일 점검 — 조치 [fix: param]
# 값: files=SUID/SGID 를 뺄 파일 절대 경로(쉼표 구분) - 진단 증적의 SUID/SGID 파일 중 운영자가 불필요하다고 판단한 것
# 변경: 지정 파일의 SUID·SGID 비트 제거(chmod u-s,g-s) - 소유자·나머지 권한은 그대로
# 영향: 일반 사용자가 지정 프로그램으로 하던 권한 상승 동작(비밀번호 변경·장치 접근 등) 즉시 실패
# 가이드 조치 방법: 불필요한 SUID/SGID 설정 제거(chmod -s). 필요 여부 판단은 사람이 한다(진단은 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 절대 경로·심볼릭 링크 아닌 일반 파일·실제로 SUID/SGID 가 있음·중복 없음.
# 관리자 접속 수단이 끊기는 sudo·su·passwd·unix_chkpwd(PAM 비밀번호 확인)는 값에 있어도 거부한다(F3).
run_fix() {
    files=$(fix_param files)
    if [ -z "$files" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 U-23.files 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
    fi
    case "${OS_FAMILY:-}" in
        rhel|debian|suse) ;;
        *) FIX_STATUS="ERROR"; FIX_DETAIL="값 지정 조치는 Linux 전용(이 환경 ${OS_FAMILY:-알 수 없음}은 수동 조치)"; FIX_EVIDENCE=""; return ;;
    esac
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
        case "$(basename "$f")" in sudo|su|passwd|unix_chkpwd) errs="$errs / $f: 관리자 접속에 필요한 파일이라 자동으로 바꾸지 않음"; continue ;; esac
        if [ -L "$f" ] || [ ! -f "$f" ]; then errs="$errs / $f: 일반 파일이 아님(없거나 심볼릭 링크·디렉터리)"; continue; fi
        [ -n "$(find "$f" -prune \( -perm -04000 -o -perm -02000 \) 2>/dev/null)" ] || errs="$errs / $f: SUID/SGID 가 없음"
    done <<EOF
$files
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    # 먼저 모두 백업(소유자·권한 8진수 - SUID/SGID 비트 포함, 원복 시 그대로 되돌림)
    while IFS= read -r f; do
        [ -n "$f" ] && fix_backup_owner "$f"
    done <<EOF
$files
EOF
    failed=""; ev=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        chmod u-s,g-s "$f" 2>/dev/null
        [ -z "$(find "$f" -prune \( -perm -04000 -o -perm -02000 \) 2>/dev/null)" ] || failed="$failed $f"
        ev="$ev$(ls -l "$f" 2>/dev/null)
"
    done <<EOF
$files
EOF
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="SUID/SGID 제거 실패:$failed"; FIX_EVIDENCE="$ev"; return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="지정 파일 $(printf '%s\n' "$files" | grep -c .)개의 SUID/SGID 를 제거함"
    FIX_EVIDENCE="$ev"
}
