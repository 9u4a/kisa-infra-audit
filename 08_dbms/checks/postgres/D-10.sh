# D-10 (상) 원격에서 DB 서버로의 접속 제한 [PostgreSQL]
# 판단 기준(가이드 원문): 양호 = 지정된 IP에서만 접근 가능하도록 제한 / 취약 = 제한 없음
# pg_hba.conf 에서 host 계열 행의 "주소" 열(4번째)이 0.0.0.0/0 · ::/0 · all · "0.0.0.0 0.0.0.0"(주소+마스크
# 형식)이면 전체 허용으로 보고 취약. 주석(#)/빈 줄은 먼저 제거한 뒤 검사한다.
# 진단 검수 D-R3: 예전에는 ①읽지 못한 파일을 "규칙 없음"=GOOD ②database/user 열의 `all` 에도 걸려 거짓 VULN
# ③주소+마스크 형식·include 지시어를 놓쳤다. 열 위치로 판정하고, 읽기 실패는 ERROR, include 가 있으면
# 그 파일까지는 보지 않으므로 전체 허용 규칙이 없을 때 MANUAL 로 남긴다.
run_check() {
    db_remote_skip "pg_hba.conf" && return
    if ! command -v psql >/dev/null 2>&1; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="psql 클라이언트가 없음"; CHECK_EVIDENCE=""
        return
    fi
    hba=$(postgres_hba_path)
    if [ -z "$hba" ] || [ ! -f "$hba" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="pg_hba.conf 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    if [ ! -r "$hba" ] || ! raw=$(sed 's/#.*$//' "$hba" 2>/dev/null); then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="pg_hba.conf 를 읽을 수 없음(권한 부족) - 확인하지 못함: $hba"; CHECK_EVIDENCE=""
        return
    fi
    active=$(printf '%s\n' "$raw" | grep -Ev '^[[:space:]]*$')
    open=$(printf '%s\n' "$active" | awk '
        $1 ~ /^host/ {
            a = $4; m = $5
            if (a == "all" || a == "0.0.0.0/0" || a == "::/0" || a == "::0/0" || a == "0/0" ||
                (a == "0.0.0.0" && m == "0.0.0.0") || (a == "::" && m == "::")) print
        }')
    incl=$(printf '%s\n' "$active" | awk '$1 ~ /^include/')
    CHECK_EVIDENCE="[$hba]
$active"
    if [ -n "$open" ]; then
        CHECK_STATUS="VULN"; CHECK_DETAIL="pg_hba.conf 에 모든 IP를 허용하는 host 규칙이 존재함: $open"
    elif [ -n "$incl" ]; then
        CHECK_STATUS="MANUAL"; CHECK_DETAIL="이 파일에는 전체 허용 규칙이 없으나 include 지시어로 불러오는 파일은 확인하지 않음 - 수동 확인 필요: $incl"
    else
        CHECK_STATUS="GOOD"; CHECK_DETAIL="pg_hba.conf 에 전체 허용(0.0.0.0/0 등) host 규칙이 없음"
    fi
}
