# 01_unix/tests/Dockerfile — debian:12 기반 회귀 테스트 이미지(vuln/hardened 공용, 상태는
# 런타임에 fixtures/setup.sh 로 적용한다 - /etc/hosts 등 일부 파일이 BuildKit 빌드 단계에서는
# read-only 로 마운트되어 RUN 중 chmod 가 실패하는 문제가 있었다, 실기 테스트로 발견).
# 빌드 컨텍스트는 저장소 루트여야 한다(01_unix/run.sh가 ../lib/common.sh를 상대경로로 참조):
#   docker build -f 01_unix/tests/Dockerfile -t kisa-u01-test .
# rhel 계열은 이 전역 픽스처(기대값 고정)에는 없고, 1.5.0 부터 Dockerfile.cases.rhel(Rocky Linux 9)에서 항목별 케이스와
# 진단 실기 안전 검사로 검증한다(run_tests.sh).
FROM debian:12

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq procps openssh-server > /dev/null && \
    rm -rf /var/lib/apt/lists/*

COPY . /infra
WORKDIR /infra
