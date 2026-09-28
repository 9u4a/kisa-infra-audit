# U-08 (중) 관리자 그룹에 최소한의 계정 포함
# 판단 기준(가이드 원문): 양호 = 관리자 그룹(root, GID 0)에 불필요한 계정이 없는 경우
#                        취약 = 불필요한 계정이 등록된 경우
# "불필요"는 조직 운영 맥락에 달려 있어 완전 자동 판정이 불가능하다.
# 자동화 범위: GID 0(root) 그룹 및 wheel/sudo 그룹 구성원을 근거로 제시, 최종 판단은 수동.

run_check() {
    group_file="/etc/group"
    if [ ! -r "$group_file" ]; then
        CHECK_STATUS="ERROR"
        CHECK_DETAIL="$group_file 파일을 읽을 수 없음 (권한 부족)"
        CHECK_EVIDENCE=""
        return
    fi

    root_group=$(awk -F: '$3 == 0 {print}' "$group_file")
    admin_groups=$(awk -F: '$1 == "wheel" || $1 == "sudo" || $1 == "admin" {print}' "$group_file")

    CHECK_STATUS="MANUAL"
    CHECK_DETAIL="관리자 그룹 구성원의 '불필요' 여부는 조직 운영 정보가 필요해 자동 판정할 수 없음. 아래 그룹 구성원 목록을 근거로 수동 검토 필요"
    CHECK_EVIDENCE="[GID 0(root) 그룹]
${root_group:-없음}

[wheel/sudo/admin 그룹]
${admin_groups:-없음}"
}
