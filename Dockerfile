ARG BASE=debian:12.11-slim
FROM $BASE AS minimal

ARG PG_VERSION
ARG PG_MAJOR

ENV PATH=$PATH:/usr/lib/postgresql/$PG_MAJOR/bin

RUN apt-get update && \
    apt-get install -y --no-install-recommends postgresql-common ca-certificates gnupg && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y -c "${PG_MAJOR}" && \
    apt-get install -y --no-install-recommends -o Dpkg::::="--force-confdef" -o Dpkg::::="--force-confold" postgresql-common && \
    sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf && \
    apt-get install -y --no-install-recommends \
      -o Dpkg::::="--force-confdef" -o Dpkg::::="--force-confold" "postgresql-${PG_MAJOR}=${PG_VERSION}*" && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    rm -rf /var/lib/apt/lists/* /var/cache/* /var/log/*

RUN usermod -u 26 postgres
USER 26


FROM minimal AS standard
ARG EXTENSIONS
ARG PRELOAD_LIBRARIES
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://repo.pigsty.io/key | gpg --dearmor -o /etc/apt/keyrings/pigsty.gpg && \
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME") && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.io/apt/pgsql/${CODENAME} ${CODENAME} main" > /etc/apt/sources.list.d/pigsty.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends locales-all ${EXTENSIONS} && \
    rm /etc/apt/sources.list.d/pigsty.list && \
    rm -f /etc/apt/keyrings/pigsty.gpg && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false curl gnupg ca-certificates && \
    rm -rf /var/lib/apt/lists/* /var/cache/* /var/log/*

USER 26

CMD ["postgres", "-c", "shared_preload_libraries=${PRELOAD_LIBRARIES}"]
