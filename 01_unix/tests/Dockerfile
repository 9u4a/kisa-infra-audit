# 01_unix/tests/Dockerfile — debian:12 기반 회귀 테스트 이미지(vuln/hardened 공용, 상태는
# 런타임에 fixtures/setup.sh 로 적용한다 - /etc/hosts 등 일부 파일이 BuildKit 빌드 단계에서는
# read-only 로 마운트되어 RUN 중 chmod 가 실패하는 문제가 있었다, 실기 테스트로 발견).
# 빌드 컨텍스트는 저장소 루트여야 한다(01_unix/run.sh가 ../lib/common.sh를 상대경로로 참조):
#   docker build -f 01_unix/tests/Dockerfile -t kisa-u01-test .
# rhel 계열(rockylinux 등)은 아직 이 픽스처에 포함하지 않았다 - 01_unix/CLAUDE.md "테스트
# 커버리지" 절 참고. 대부분의 check가 "rhel|debian|suse)" 공용 분기라 debian 검증이 상당 부분
# 대표성을 갖지만, 배포판 전용 경로/패키지명 차이는 아직 커버하지 못한다.
FROM debian:12

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq procps openssh-server > /dev/null && \
    rm -rf /var/lib/apt/lists/*

COPY . /infra
WORKDIR /infra
