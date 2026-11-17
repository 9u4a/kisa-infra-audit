# U-25 (상) world writable 파일 점검 — 조치 [fix: param]
# 값: files=다른 사용자 쓰기 권한을 뺄 파일 절대 경로(쉼표 구분) - 진단 증적의 world writable 파일 중 설정 이유가 없는 것
# 변경: 지정 파일의 다른 사용자(other) 쓰기 권한 제거(chmod o-w) - 소유자·나머지 권한은 그대로
# 영향: 소유자·그룹이 아닌 계정이 지정 파일에 쓰던 동작(로그 기록·공유 파일 갱신 등) 즉시 실패
# 가이드 조치 방법: 설정 이유를 모르는 world writable 파일의 일반 사용자 쓰기 권한 제거(chmod o-w).
# 이유 인지 여부는 사람이 판단한다(진단은 MANUAL, 1.7.0 값 지정 조치).
# 값 검증(하나라도 틀리면 아무것도 바꾸지 않음): 절대 경로·심볼릭 링크 아닌 일반 파일·실제로 other 쓰기 권한이 있음·중복 없음.
run_fix() {
    files=$(fix_param files)
    if [ -z "$files" ]; then
        FIX_STATUS="MANUAL"; FIX_DETAIL="정책 값 U-25.files 가 없어 바꾸지 않음"; FIX_EVIDENCE=""; return
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
        if [ -L "$f" ] || [ ! -f "$f" ]; then errs="$errs / $f: 일반 파일이 아님(없거나 심볼릭 링크·디렉터리)"; continue; fi
        [ -n "$(find "$f" -prune -perm -0002 2>/dev/null)" ] || errs="$errs / $f: 다른 사용자 쓰기 권한이 없음"
    done <<EOF
$files
EOF
    if [ -n "$errs" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="값 검증 실패 - 아무것도 바꾸지 않음:${errs# /}"; FIX_EVIDENCE=""; return
    fi

    while IFS= read -r f; do
        [ -n "$f" ] && fix_backup_owner "$f"
    done <<EOF
$files
EOF
    failed=""; ev=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        chmod o-w "$f" 2>/dev/null
        [ -z "$(find "$f" -prune -perm -0002 2>/dev/null)" ] || failed="$failed $f"
        ev="$ev$(ls -l "$f" 2>/dev/null)
"
    done <<EOF
$files
EOF
    if [ -n "$failed" ]; then
        FIX_STATUS="ERROR"; FIX_DETAIL="다른 사용자 쓰기 권한 제거 실패:$failed"; FIX_EVIDENCE="$ev"; return
    fi
    FIX_STATUS="APPLIED"
    FIX_DETAIL="지정 파일 $(printf '%s\n' "$files" | grep -c .)개의 다른 사용자 쓰기 권한을 제거함"
    FIX_EVIDENCE="$ev"
}
