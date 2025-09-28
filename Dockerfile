FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/games:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       fortune-mod fortunes cowsay netcat-openbsd ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1001 wisecow \
    && useradd -r -u 1001 -g wisecow -s /bin/bash -m wisecow

WORKDIR /app

COPY wisecow.sh /usr/local/bin/wisecow.sh
RUN chmod +x /usr/local/bin/wisecow.sh \
    && chown -R wisecow:wisecow /app

USER 1001:1001

EXPOSE 4499

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s CMD nc -z localhost 4499 || exit 1

ENTRYPOINT ["/usr/local/bin/wisecow.sh"]
