# U-50 (상) DNS ZoneTransfer 설정
# 판단 기준(가이드 원문): 양호 = Zone Transfer 를 허가된 사용자에게만 허용 / 취약 = 전체 허용
# 자동화 범위: BIND(named.conf 와 include 된 파일 전체) allow-transfer 설정. DNS 미사용 시 GOOD.
# 진단 검수 U-R5: 예전에는 include 만 있는 Debian /etc/bind/named.conf 를 골라 grep 첫 줄만 봤다(주석 속 값·
# 여러 줄 블록·include 파일 미처리). 이제 lib/common.sh named_conf_flatten 으로 include 를 따라가 문장 단위로 본다.
# 판정: allow-transfer 중 하나라도 any → 취약. options 에 allow-transfer 가 없으면 기본값(any)이 적용되므로
#       master/slave 존마다(존 또는 상위 view 에) allow-transfer 가 있어야 양호.

run_check() {
    conf=""
    for f in /etc/named.conf /etc/bind/named.conf /etc/bind/named.conf.options; do
        [ -f "$f" ] && { conf="$f"; break; }
    done

    if [ -z "$conf" ]; then
        if command -v named >/dev/null 2>&1; then
            CHECK_STATUS="MANUAL"
            CHECK_DETAIL="named 는 설치되어 있으나 설정 파일 위치를 찾지 못함"
        else
            CHECK_STATUS="GOOD"
            CHECK_DETAIL="DNS 서비스(BIND/named)가 설치되어 있지 않음"
        fi
        CHECK_EVIDENCE=""
        return
    fi

    recs=$(named_conf_flatten "$conf")
    files=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "@file" { printf "%s ", $2 }')
    unread=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "!unread" { printf "%s ", $2 }')
    xfer=$(printf '%s\n' "$recs" | awk -F'\t' '$2 == "allow-transfer" { print $1 ": allow-transfer {" $3 " }" }')
    any_l=$(printf '%s\n' "$recs" | awk -F'\t' '$2 == "allow-transfer" && (" " $3 " ") ~ / any / { print $1 }')
    opt=$(printf '%s\n' "$recs" | awk -F'\t' '$1 == "options" && $2 == "allow-transfer"')
    # 존(master/primary/slave/secondary) 중 자신 또는 상위 view 에 allow-transfer 가 없는 것
    open_z=$(printf '%s\n' "$recs" | awk -F'\t' '
        $2 == "allow-transfer" { a[$1] = 1 }
        $2 == "type" && ($3 == "master" || $3 == "primary" || $3 == "slave" || $3 == "secondary") { z[$1] = 1 }
        END { for (c in z) { if (a[c]) continue; p = c; sub(/ > [^>]*$/, "", p); if (p != c && a[p]) continue; print c } }')
    nzone=$(printf '%s\n' "$recs" | awk -F'\t' '$2 == "type" && ($3 == "master" || $3 == "primary" || $3 == "slave" || $3 == "secondary")' | grep -c .)
    CHECK_EVIDENCE="설정 파일: ${files}
${xfer:-allow-transfer 미설정}"
    [ -n "$unread" ] && CHECK_EVIDENCE="$CHECK_EVIDENCE
읽지 못한 include: $unread"

    if [ -n "$any_l" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="allow-transfer 가 any(전체 허용)로 설정되어 있음: $(printf '%s' "$any_l" | tr '\n' ' ')"
    elif [ -z "$opt" ] && [ -n "$open_z" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="options 에 allow-transfer 가 없고(기본값 전체 허용) 다음 존에도 제한이 없음: $(printf '%s' "$open_z" | head -n 10 | tr '\n' ' ')"
    elif [ -z "$opt" ] && [ "$nzone" -eq 0 ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="allow-transfer 설정이 없어 기본적으로 모든 사용자에게 Zone Transfer 가 허용됨"
    elif [ -n "$unread" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="include 된 설정 파일을 읽지 못해 allow-transfer 설정 전체를 확인하지 못함"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="allow-transfer 가 특정 대상으로 제한되어 있음"
    fi
}
