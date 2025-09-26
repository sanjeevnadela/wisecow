FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/games:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       fortune-mod fortunes cowsay netcat-openbsd ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY wisecow.sh /app/wisecow.sh
RUN chmod +x /app/wisecow.sh

EXPOSE 4499

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s CMD nc -z localhost 4499 || exit 1

ENTRYPOINT ["/app/wisecow.sh"]
