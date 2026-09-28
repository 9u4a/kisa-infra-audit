# D-10 (상) 원격에서 DB 서버로의 접속 제한 [Oracle]
# 판단 기준(가이드 원문): 양호 = 지정된 IP에서만 접근 가능하도록 제한 / 취약 = 제한 없음
# sqlnet.ora 의 tcp.validnode_checking = yes 및 tcp.invited_nodes 설정 여부로 판단한다.
run_check() {
    f=$(oracle_sqlnet_ora)
    if [ -z "$f" ]; then
        CHECK_STATUS="ERROR"; CHECK_DETAIL="sqlnet.ora 파일을 찾을 수 없음"; CHECK_EVIDENCE=""
        return
    fi
    checking=$(grep -i 'tcp\.validnode_checking' "$f")
    invited=$(grep -i 'tcp\.invited_nodes' "$f")
    CHECK_EVIDENCE="[$f]
$checking
$invited"
    if printf '%s' "$checking" | grep -qi 'yes'; then
        CHECK_STATUS="GOOD"; CHECK_DETAIL="tcp.validnode_checking=yes 로 접속 IP 제한이 설정되어 있음"
    else
        CHECK_STATUS="VULN"; CHECK_DETAIL="sqlnet.ora 에 tcp.validnode_checking=yes 설정이 없어 접속 IP 제한이 없음"
    fi
}
