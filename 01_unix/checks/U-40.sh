# U-40 (상) NFS 접근 통제
# 판단 기준(가이드 원문): 양호 = 접근 통제가 설정되어 있으며 NFS 설정 파일 권한이 644 이하
#                        취약 = 접근 통제 미설정 및 권한이 644 초과
# 자동화 범위: /etc/exports 와 /etc/exports.d/*.exports 의 권한(644 이하) + 전체 공개 공유 여부.
# 진단 검수 U-R15: 예전에는 /etc/exports 만 보고 "*" 호스트만 전체 공개로 셌다. exports(5) 상 호스트를 생략한
# "/srv (rw)"·"/srv" 도 모든 호스트에 공개되므로 같이 위반으로 본다. 주석(#) 줄은 제외.

run_check() {
    files=""
    for f in /etc/exports /etc/exports.d/*.exports; do
        [ -s "$f" ] && files="$files $f"
    done
    if [ -z "$files" ]; then
        CHECK_STATUS="NA"
        CHECK_DETAIL="NFS 미사용 (/etc/exports·/etc/exports.d 없음 또는 비어 있음)"
        CHECK_EVIDENCE=""
        return
    fi

    bad_perm=""
    evidence=""
    open_lines=""
    for f in $files; do
        perm=$(stat -L -c '%a' "$f" 2>/dev/null)
        if [ -z "$perm" ] || ! perm_within "$perm" 644; then
            bad_perm="$bad_perm $f(${perm:-확인불가})"
        fi
        lines=$(grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null)
        # 첫 필드=경로, 나머지=호스트(옵션). 호스트 없이 옵션만 있거나("(" 로 시작) 필드가 경로뿐이거나 "*" 이면 전체 공개.
        o=$(printf '%s\n' "$lines" | awk 'NF == 0 { next } NF == 1 { print; next } { for (i = 2; i <= NF; i++) if ($i ~ /^\(/ || $i ~ /^\*(\(|$)/) { print; next } }')
        [ -n "$o" ] && open_lines="$open_lines
$f: $o"
        evidence="$evidence
$(ls -l "$f" 2>/dev/null)
공유 설정:
$lines"
    done

    if [ -z "$bad_perm" ] && [ -z "$open_lines" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="NFS 설정 파일 권한이 644 이하이며 전체 공개(* 또는 호스트 생략) 공유가 없음"
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="NFS 접근 통제 미흡:${bad_perm:+ 권한 644 초과($bad_perm )}${open_lines:+ 전체 공개(* 또는 호스트 생략) 공유 존재}"
        [ -n "$open_lines" ] && evidence="$evidence
전체 공개 공유:$open_lines"
    fi
    CHECK_EVIDENCE=$(printf '%s' "$evidence" | sed '1{/^$/d}')
}
