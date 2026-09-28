# U-09 (하) 계정이 존재하지 않는 GID 금지
# 판단 기준(가이드 원문): 양호 = 불필요한 그룹이 제거된 경우 / 취약 = 존재하는 경우
# 조치 방법 원문("/etc/group 파일과 /etc/passwd 파일을 비교하여 점검")에 따라, /etc/passwd 의
# 기본 GID(4번째 필드)가 /etc/group 에 정의되어 있지 않은 "존재하지 않는 GID(고아 GID)"를 탐지한다.
# 전 Unix 계열 공통 로직 (환경 구분 불필요).

run_check() {
    passwd_file="/etc/passwd"; group_file="/etc/group"
    if [ ! -r "$passwd_file" ] || [ ! -r "$group_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="/etc/passwd 또는 /etc/group 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    group_gids=$(awk -F: '{print $3}' "$group_file" | sort -un)
    orphan=$(awk -F: '{print $1":"$4}' "$passwd_file" | while IFS=: read -r name gid; do
        if ! printf '%s\n' "$group_gids" | grep -qx "$gid"; then
            echo "$name (gid=$gid)"
        fi
    done)

    if [ -z "$orphan" ]; then
        CHECK_STATUS="GOOD"
        CHECK_DETAIL="/etc/passwd 의 모든 기본 GID가 /etc/group 에 정의되어 있음 (존재하지 않는 GID 없음)"
        CHECK_EVIDENCE=""
    else
        CHECK_STATUS="VULN"
        CHECK_DETAIL="/etc/group 에 정의되지 않은 GID를 기본 그룹으로 사용하는 계정이 존재함"
        CHECK_EVIDENCE="$orphan"
    fi
}
