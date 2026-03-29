FROM alpine:3.21 AS builder

# Static build dependencies — includes both the .so and .a variants
# bison is required by PostgreSQL 17+ configure even from release tarballs
RUN apk add --no-cache \
    build-base \
    linux-headers \
    wget \
    bison \
    flex \
    perl \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    readline-dev \
    readline-static \
    ncurses-dev \
    ncurses-static

ARG PG_VERSION

RUN wget -q https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.gz \
    && tar xzf postgresql-${PG_VERSION}.tar.gz \
    && rm postgresql-${PG_VERSION}.tar.gz

WORKDIR /postgresql-${PG_VERSION}

# Configure normally (no -static in LDFLAGS — that breaks the shared libpq.so
# build with a crtbeginT.o relocation error).
RUN ./configure \
    --prefix=/out \
    --with-openssl \
    --with-readline \
    --without-icu \
    --without-ldap \
    --without-gssapi \
    --without-pam \
    --without-perl \
    --without-python \
    --without-tcl \
    CFLAGS="-O2"

# Build only the libraries psql needs, then the psql binary itself.
RUN make -j$(nproc) -C src/common \
 && make -j$(nproc) -C src/port \
 && make -j$(nproc) -C src/interfaces/libpq \
 && make -j$(nproc) -C src/fe_utils \
 && make -j$(nproc) -C src/bin/psql

# Static re-link.  Two subtleties vs a plain LDFLAGS=-static approach:
#
#  1. Object discovery: `ls *.o` is used instead of a hardcoded list so that
#     new source files added in PG17+ (e.g. unicode helpers) are included.
#
#  2. --start-group/--end-group: pg libraries have circular symbol references
#     (libpq ↔ libpgcommon ↔ libpgport); the group flag makes ld rescan until
#     all symbols are resolved regardless of order.
#
#  3. -lncurses after -lreadline: readline.a references tputs/tgetnum/etc.
#     which configure omits from LIBS (they're found dynamically at configure
#     time); for static linking they must be listed explicitly.
RUN cd src/bin/psql \
 && OBJS=$(ls *.o | tr '\n' ' ') \
 && gcc $OBJS \
    -static \
    -Wl,--start-group \
      -L../../fe_utils         -lpgfeutils \
      -L../../interfaces/libpq -lpq \
      -L../../common           -lpgcommon_shlib \
      -L../../port             -lpgport_shlib \
      -lssl -lcrypto -lz \
      -lreadline -lncurses \
    -Wl,--end-group \
    -lm \
    -o psql \
 && strip psql

# Verify
RUN file src/bin/psql/psql \
 && (ldd src/bin/psql/psql 2>&1 || echo "OK: statically linked") \
 && src/bin/psql/psql --version

# Stage at a fixed path so the COPY below works regardless of PG_VERSION
RUN cp src/bin/psql/psql /psql

FROM scratch
COPY --from=builder /psql /psql
