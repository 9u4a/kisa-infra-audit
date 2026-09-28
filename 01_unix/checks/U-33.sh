# U-33 (하) 숨겨진 파일 및 디렉토리 검색 및 제거
# 판단 기준(가이드 원문): 양호 = 의심스러운 숨겨진 파일/디렉토리를 제거한 경우
#                        취약 = 제거하지 않은 경우
# "의심스러움"은 기계적으로 판단할 수 없으므로 홈 디렉토리 내 숨김 파일 목록을 근거로 제시하고
# MANUAL 로 응답한다 (.ssh, .cache, .config, .bash_history 등 통상적인 항목은 제외).

run_check() {
    passwd_file="/etc/passwd"
    if [ ! -r "$passwd_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$passwd_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    common_allowlist='\.(ssh|cache|config|local|bash_history|bash_logout|bashrc|bash_profile|profile|viminfo|lesshst|gnupg|mozilla|Xauthority)$'
    homes=$(awk -F: '{print $6}' "$passwd_file" | sort -u)
    findings=""
    for h in $homes; do
        [ -d "$h" ] || continue
        f=$(find "$h" -maxdepth 2 -name '.*' 2>/dev/null | grep -vE "$common_allowlist" | grep -vE '^\.$|/\.$|/\.\.$')
        [ -n "$f" ] && findings="$findings
$f"
    done

    CHECK_STATUS="MANUAL"
    if [ -z "$findings" ]; then
        CHECK_DETAIL="통상적인 항목을 제외한 숨겨진 파일/디렉토리가 발견되지 않음 (그래도 정기적 수동 점검 권고)"
    else
        CHECK_DETAIL="통상적인 항목을 제외한 숨겨진 파일/디렉토리가 발견됨 — 의심스러운 항목인지 수동 검토 필요"
    fi
    CHECK_EVIDENCE="${findings:-없음}"
}
