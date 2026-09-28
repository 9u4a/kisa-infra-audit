# U-40 (상) NFS 접근 통제
# 판단 기준(가이드 원문): 양호 = 접근 통제가 설정되어 있으며 NFS 설정 파일 권한이 644 이하
#                        취약 = 접근 통제 미설정 및 권한이 644 초과
# 자동화 범위: LINUX 기준 /etc/exports.

run_check() {
    exports="/etc/exports"
    if [ ! -s "$exports" ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="NFS 미사용 ($exports 없음 또는 비어 있음)"
        CHECK_EVIDENCE=""
        return
    fi

    perm=$(stat -c '%a' "$exports" 2>/dev/null)
    lines=$(grep -vE '^[[:space:]]*(#|$)' "$exports")
    open_lines=$(printf '%s\n' "$lines" | grep -E '(^|[[:space:]])\*(\(|[[:space:]])')

    evidence="$(ls -l "$exports" 2>/dev/null)
공유 설정:
$lines"

    if [ -n "$perm" ] && [ "$perm" -le 644 ] 2>/dev/null && [ -z "$open_lines" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="$exports 권한(${perm})이 644 이하이며 전체 공개(*) 공유가 없음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="$exports 권한이 644를 초과하거나(${perm:-확인불가}) 전체 공개(*) 공유가 존재함"
    fi
    CHECK_EVIDENCE="$evidence"
}
