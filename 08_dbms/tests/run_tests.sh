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
# 매번 26항목 전체를 돌려 다른 항목의 회귀도 함께 잡아낸다). "원격 클라이언트 컨테이너에서
# run.sh 실행" 토폴로지라 로컬 파일·프로세스 기반 항목(MySQL D-07/D-14, PostgreSQL D-10/D-14)은
# 원격 모드 MANUAL 로 나와야 한다(진단 검수 D-R1 - 예전에는 클라이언트 컨테이너의 /etc/my.cnf 로
# D-14 를 판정했다). vuln 모드에서는 권한 없는 계정(lowpriv)으로 한 번 더 진단해 권한 부족 항목이
# GOOD/VULN 대신 ERROR 인지 확인한다(D-R2).
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
                if [ $mode = vuln ]; then
                    DB_PASSWORD='LowPriv123!' sh 08_dbms/run.sh -e $engine --host dbhost --user lowpriv -o /tmp/out_low >/dev/null 2>&1
                    cp /tmp/out_low/*/result.json /result_lowpriv.json
                fi
            ")
            docker start -a "$cid" >/dev/null
            result_file="result_${engine}_${mode}.json"
            docker cp "$cid:/result.json" "$result_file" >/dev/null 2>&1
            low_file="result_${engine}_lowpriv.json"
            [ "$mode" = "vuln" ] && docker cp "$cid:/result_lowpriv.json" "$low_file" >/dev/null 2>&1
            docker rm "$cid" >/dev/null

            # 권한 없는 계정 진단: 전체를 볼 수 없는 항목은 GOOD/VULN 이 아니라 ERROR 여야 한다(진단 검수 D-R2)
            if [ "$mode" = "vuln" ]; then
                if [ ! -f "$low_file" ]; then
                    echo "FAIL: $engine/lowpriv - 권한 없는 계정 진단 결과를 꺼내지 못함"; fail=1
                elif python3 - "$low_file" "$engine/lowpriv" <<'PYEOF'
import json, sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
path, label = sys.argv[1], sys.argv[2]
st = {it["code"]: (it["status"], it["detail"]) for it in json.load(open(path, encoding="utf-8"))["items"]}
must_error = ["D-01", "D-08", "D-11"]
bad = [c for c in must_error if st.get(c, ("?", ""))[0] != "ERROR"]
if bad:
    print(f"FAIL: {label} - 권한 부족 항목이 ERROR 가 아님")
    for c in must_error:
        print(f"  - {c}: {st.get(c)}")
    sys.exit(1)
print(f"PASS: {label} ({', '.join(must_error)} = ERROR)")
PYEOF
                then :; else fail=1; fi
                rm -f "$low_file"
            fi

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

# ---- 진단이 DB 에 읽기 전용 문장만 보내는지(운영 안전 기준 S1, 진단 실행 검수) ------------------------
# DB 서버가 실제로 받은 문장을 서버 쪽 로그(MySQL general_log, PostgreSQL log_statement=all)로 모아, 첫 키워드가
# SELECT/SHOW/세션 범위 SET 등인지 lib/tests/run_safety_check.py 의 SQL_OK 로 확인한다. 픽스처 적용 뒤부터만 센다.
for engine in mysql postgres; do
    image="kisa-dbms-${engine}-test"
    net="kisa-dbms-net-$$-$engine-sql"
    docker network create "$net" >/dev/null
    if [ "$engine" = "mysql" ]; then
        db_cid=$(docker run -d --network "$net" --network-alias dbhost -e MYSQL_ROOT_PASSWORD=TestRoot123! mysql:8); dbuser="root"
    else
        db_cid=$(docker run -d --network "$net" --network-alias dbhost -e POSTGRES_PASSWORD=TestRoot123! postgres:16); dbuser="postgres"
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
    sqlf="sql_${engine}_$$.log"
    if [ "$ready" -ne 1 ]; then
        echo "FAIL: $engine/sql-readonly - DB 서버가 60초 내에 준비되지 않음"; fail=1
    else
        if [ "$engine" = "mysql" ]; then
            on="mysql -h dbhost -uroot -pTestRoot123! -e \"SET GLOBAL log_output='TABLE'; TRUNCATE mysql.general_log; SET GLOBAL general_log='ON';\""
            off="mysql -h dbhost -uroot -pTestRoot123! -N -B -e \"SET GLOBAL general_log='OFF'; SELECT argument FROM mysql.general_log WHERE command_type IN ('Query','Execute');\""
        else
            on="PGPASSWORD=TestRoot123! psql -h dbhost -U postgres -qAt -c \"ALTER SYSTEM SET log_statement='all'\" -c 'SELECT pg_reload_conf()' >/dev/null; sleep 1; PGPASSWORD=TestRoot123! psql -h dbhost -U postgres -qAt -c \"SELECT 'kisa_sql_begin'\" >/dev/null"
            off="PGPASSWORD=TestRoot123! psql -h dbhost -U postgres -qAt -c \"SELECT 'kisa_sql_end'\" >/dev/null"
        fi
        docker run --rm --network "$net" -e DB_HOST=dbhost -e DB_PASSWORD=TestRoot123! "$image" sh -c "
            sh 08_dbms/tests/fixtures/setup.sh $engine vuln >/dev/null 2>&1
            $on 2>/dev/null
            sh 08_dbms/run.sh -e $engine --host dbhost --user $dbuser -o /tmp/out >/dev/null 2>&1
            $off 2>/dev/null" > "$sqlf"
        if [ "$engine" = "postgres" ]; then
            docker logs "$db_cid" 2>&1 | awk '/kisa_sql_begin/ { on = 1; next } /kisa_sql_end/ { on = 0 }
                on && /LOG:  statement: / { sub(/.*LOG:  statement: /, ""); print }' > "$sqlf"
        fi
        python3 - "$sqlf" "$engine" <<'PYEOF' || fail=1
import sys
sys.path.insert(0, "lib/tests")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
from run_safety_check import SQL_OK
path, engine = sys.argv[1], sys.argv[2]
stmts = []
for line in open(path, encoding="utf-8", errors="replace").read().splitlines():
    # psql 은 -c 한 번에 여러 문장을 보낸다 - 세미콜론마다 나눠 각각 본다(문자열 속 ; 는 드물고, 있어도 SELECT 안이다)
    stmts += [s.strip() for s in line.split(";") if s.strip()]
stmts = [s for s in stmts if "general_log" not in s and "kisa_sql_" not in s]
bad = [s for s in stmts if not SQL_OK.match(s)]
if not stmts:
    print(f"FAIL: {engine}/sql-readonly - 쿼리 로그가 비어 있음(수집 실패 - 검증 불가)"); sys.exit(1)
if bad:
    print(f"FAIL: {engine}/sql-readonly - 읽기 전용이 아닌 문장 {len(bad)}건")
    for b in bad[:20]:
        print("  - " + b[:200])
    sys.exit(1)
print(f"PASS: {engine}/sql-readonly (DB 로 보낸 문장 {len(stmts)}건 모두 읽기 전용)")
PYEOF
    fi
    rm -f "$sqlf"
    docker rm -f "$db_cid" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
done

exit $fail
