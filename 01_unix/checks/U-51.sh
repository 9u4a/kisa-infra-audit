# U-51 (중) DNS 서비스의 취약한 동적 업데이트 설정 금지
# 판단 기준(가이드 원문): 양호 = 동적 업데이트 비활성화 또는 활성화 시 접근통제 적용
#                        취약 = 활성화되어 있고 접근통제 없음
# 자동화 범위: BIND(named.conf 와 include 된 파일 전체) allow-update 설정. DNS 미사용 시 GOOD.
# 진단 검수 U-R5: include 만 있는 Debian /etc/bind/named.conf 의 grep 첫 줄만 봐서 include·주석·여러 줄 블록을
# 처리하지 못했다 - lib/common.sh named_conf_flatten 으로 펼쳐서 모든 allow-update 를 본다.
# 판정: allow-update 중 하나라도 any → 취약. 미설정이면 BIND 기본값 none(비활성화), update-policy 는 접근통제로 본다.

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
    upd=$(printf '%s\n' "$recs" | awk -F'\t' '$2 == "allow-update" || $2 == "update-policy" { print $1 ": " $2 " {" $3 " }" }')
    any_l=$(printf '%s\n' "$recs" | awk -F'\t' '$2 == "allow-update" && (" " $3 " ") ~ / any / { print $1 }')
    CHECK_EVIDENCE="설정 파일: ${files}
${upd:-allow-update 미설정(기본값 none)}"
    [ -n "$unread" ] && CHECK_EVIDENCE="$CHECK_EVIDENCE
읽지 못한 include: $unread"

    if [ -n "$any_l" ]; then
        CHECK_STATUS="VULN"
        CHECK_DETAIL="allow-update 가 any(전체 허용)로 설정되어 있음: $(printf '%s' "$any_l" | tr '\n' ' ')"
    elif [ -n "$unread" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="include 된 설정 파일을 읽지 못해 allow-update 설정 전체를 확인하지 못함"
    elif [ -z "$upd" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="allow-update 설정이 없어 동적 업데이트가 기본적으로 비활성화됨"
    else
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="동적 업데이트가 비활성화(none)되었거나 특정 대상/update-policy 로 제한되어 있음"
    fi
}
