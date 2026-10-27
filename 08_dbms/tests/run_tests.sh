#!/bin/sh
# 08_dbms/tests/run_tests.sh — Docker(공식 mysql:8/postgres:16) 기반 회귀 테스트.
# 저장소 루트에서 실행: sh 08_dbms/tests/run_tests.sh
#
# 01_unix/03_web과 달리 DB 서버와 run.sh를 실행하는 쪽이 분리되어 있어(원격 접속 모델)
# 매 (엔진,모드) 조합마다: ①전용 docker 네트워크 생성 ②DB 서버 컨테이너 기동 ③클라이언트
# 컨테이너에서 fixtures/setup.sh 적용 후 run.sh 실행 ④docker cp로 결과 추출 ⑤컨테이너/네트워크
# 정리, 순서로 진행한다. Oracle은 이미지가 무거워 여기 포함하지 않았다(CI의 별도 주간
# job 후보 - 08_dbms/CLAUDE.md "테스트 커버리지" 참고). D-11(시스템 테이블 접근 제한)만
# 명시적으로 vuln/hardened를 가르고 나머지 25항목은 각 이미지의 기본값을 반영한다(run.sh는
# 매번 26항목 전체를 돌려 다른 항목의 회귀도 함께 잡아낸다). D-10/D-14는 로컬 설정 파일
# 경로를 읽는 방식이라 "원격 클라이언트 컨테이너에서 run.sh 실행" 토폴로지에서는 항상 ERROR
# (파일을 찾을 수 없음)로 나온다 - 이는 버그가 아니라 이 테스트 구성 자체의 한계다.
set -eu
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")/../.."

fail=0
for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    echo "[빌드] $engine 클라이언트 이미지..."
    docker build -q -f "08_dbms/tests/Dockerfile.$engine" -t "$image" . >/dev/null

    for mode in vuln hardened; do
        echo "[*] $engine/$mode 픽스처 실행..."
        net="kisa-dbms-net-$$-$engine-$mode"
        docker network create "$net" >/dev/null

        if [ "$engine" = "mysql" ]; then
            db_cid=$(docker run -d --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8)
        else
            db_cid=$(docker run -d --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16)
        fi

        # DB 가 접속을 받을 때까지 대기(최대 60초)
        ready=0
        i=0
        while [ "$i" -lt 30 ]; do
            if [ "$engine" = "mysql" ]; then
                docker run --rm --network "$net" "$image" sh -c "mysqladmin ping -h dbhost -uroot -pTestRoot123! --silent" >/dev/null 2>&1 && { ready=1; break; }
            else
                docker run --rm --network "$net" -e PGPASSWORD=TestRoot123! "$image" sh -c "pg_isready -h dbhost -U postgres" >/dev/null 2>&1 && { ready=1; break; }
            fi
            i=$((i + 1))
            sleep 2
        done

        if [ "$ready" -ne 1 ]; then
            echo "FAIL: $engine/$mode - DB 서버가 60초 내에 준비되지 않음"
            fail=1
        else
            if [ "$engine" = "mysql" ]; then dbuser="root"; else dbuser="postgres"; fi
            cid=$(docker create --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD=TestRoot123! "$image" sh -c "
                sh 08_dbms/tests/fixtures/setup.sh $engine $mode >/dev/null 2>&1
                sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1
                cp /tmp/out/*/result.json /result.json
            ")
            docker start -a "$cid" >/dev/null
            result_file="result_${engine}_${mode}.json"
            docker cp "$cid:/result.json" "$result_file" >/dev/null 2>&1
            docker rm "$cid" >/dev/null

            if [ ! -f "$result_file" ]; then
                echo "FAIL: $engine/$mode - 컨테이너에서 result.json 을 꺼내지 못함"
                fail=1
            elif python3 - "$result_file" "08_dbms/tests/fixtures/expected_${engine}_${mode}.json" "$engine/$mode" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
result_path, expected_path, label = sys.argv[1], sys.argv[2], sys.argv[3]
actual = {it["code"]: it["status"] for it in json.load(open(result_path, encoding="utf-8"))["items"]}
expected = json.load(open(expected_path, encoding="utf-8"))
failures = [f"{c}: 기대={e} 실제={actual.get(c)}" for c, e in expected.items() if actual.get(c) != e]
if failures:
    print(f"FAIL: {label} - {len(failures)}건 불일치")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"PASS: {label}")
PYEOF
            then :; else fail=1; fi
            rm -f "$result_file"
        fi

        docker rm -f "$db_cid" >/dev/null 2>&1 || true
        docker network rm "$net" >/dev/null 2>&1 || true
    done
done

# ---- 운영 안전 회귀 테스트 ---------------------------------------------------------
# ① 잘못된 비밀번호로 run.sh 를 돌려도 DB 서버가 본 로그인 실패는 정확히 1회여야 한다(항목마다
#    재시도하면 Oracle FAILED_LOGIN_ATTEMPTS 등으로 운영 계정이 잠김 - lib/common.sh db_preflight).
# ② 이때 DB 조회 항목은 "사전 점검 실패" 사유의 ERROR 로 남아야 한다(거짓 GOOD/VULN 금지).
# ③ 비밀번호 없이 실행해도 프롬프트에서 멈추지 않고 끝나야 한다(psql -w, _db_run).
for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    net="kisa-dbms-net-$$-$engine-safety"
    docker network create "$net" >/dev/null
    if [ "$engine" = "mysql" ]; then
        db_cid=$(docker run -d --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8)
        dbuser="root"
    else
        db_cid=$(docker run -d --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16)
        dbuser="postgres"
    fi
    ready=0; i=0
    while [ "$i" -lt 30 ]; do
        if [ "$engine" = "mysql" ]; then
            docker run --rm --network "$net" "$image" sh -c "mysqladmin ping -h dbhost -uroot -pTestRoot123! --silent" >/dev/null 2>&1 && { ready=1; break; }
        else
            docker run --rm --network "$net" "$image" sh -c "pg_isready -h dbhost -U postgres" >/dev/null 2>&1 && { ready=1; break; }
        fi
        i=$((i + 1)); sleep 2
    done
    if [ "$ready" -ne 1 ]; then
        echo "FAIL: $engine/safety - DB 서버가 60초 내에 준비되지 않음"; fail=1
    else
        mysql_aborted() {
            docker run --rm --network "$net" "$image" sh -c \
                "mysql -h dbhost -uroot -pTestRoot123! -N -B -e \"SHOW GLOBAL STATUS LIKE 'Aborted_connects'\" 2>/dev/null" | awk '{print $2}'
        }
        before=0
        [ "$engine" = "mysql" ] && before=$(mysql_aborted)
        [ "$engine" = "postgres" ] && before=$(docker logs "$db_cid" 2>&1 | grep -c 'password authentication failed' || true)

        safety_json="result_${engine}_safety.json"
        rc=0
        docker run --rm --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD='WrongPass!9' "$image" sh -c "
            timeout 300 sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1
            echo \"rc=\$?\" >&2
            cat /tmp/out/*/result.json" > "$safety_json" 2>"$safety_json.rc" || rc=$?

        if [ "$engine" = "mysql" ]; then
            after=$(mysql_aborted)
        else
            after=$(docker logs "$db_cid" 2>&1 | grep -c 'password authentication failed' || true)
        fi
        attempts=$((after - before))
        run_rc=$(sed -n 's/^rc=//p' "$safety_json.rc")

        nopw_rc=$(docker run --rm --network "$net" -e DB_HOST=dbhost "$image" sh -c "
            timeout 300 sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1; echo \$?" || true)

        if [ "$attempts" -ne 1 ]; then
            echo "FAIL: $engine/safety - 잘못된 비밀번호로 로그인 실패 ${attempts}회 발생(기대 1회)"; fail=1
        elif [ "$run_rc" = "124" ] || [ "$nopw_rc" = "124" ]; then
            echo "FAIL: $engine/safety - run.sh 가 300초 안에 끝나지 않음(대기/프롬프트 의심)"; fail=1
        elif python3 - "$safety_json" "$engine/safety" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
path, label = sys.argv[1], sys.argv[2]
items = json.load(open(path, encoding="utf-8"))["items"]
blocked = [it for it in items if it["status"] == "ERROR" and "사전 점검 실패" in it["detail"]]
judged = [it["code"] for it in items if it["status"] in ("GOOD", "VULN") and "사전 점검" not in it["detail"]]
if not blocked:
    print(f"FAIL: {label} - '사전 점검 실패' ERROR 항목이 없음"); sys.exit(1)
print(f"PASS: {label} (로그인 실패 1회, 차단된 DB 조회 항목 {len(blocked)}개, 접속 없이 판정된 항목 {judged})")
PYEOF
        then :; else fail=1; fi
        rm -f "$safety_json" "$safety_json.rc"
    fi
    docker rm -f "$db_cid" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
done

exit $fail
