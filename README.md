# psql-static

Pre-built, fully static `psql` binaries compiled from official PostgreSQL source
against [musl libc](https://musl.libc.org/).  No shared library dependencies —
download and run on any modern Linux, including systems with old glibc or no
PostgreSQL installation at all (HPC clusters, containers, etc.).

## Download

There is one release per PostgreSQL major version — `pg15`, `pg16`, `pg17`, `pg18` —
each always tracking the latest patch.

```bash
# PostgreSQL 16, x86_64 (Intel/AMD)
curl -fsSL https://github.com/kljensen/psql-static/releases/download/pg16/psql-16.13-linux-x86_64 \
  -o psql && chmod +x psql && ./psql --version

# PostgreSQL 16, aarch64 (ARM64 / Apple Silicon Linux / Raspberry Pi)
curl -fsSL https://github.com/kljensen/psql-static/releases/download/pg16/psql-16.13-linux-aarch64 \
  -o psql && chmod +x psql && ./psql --version
```

> **Note:** The patch number in the filename (e.g. `16.13`) advances automatically
> when PostgreSQL ships a new patch release.  Check the
> [pg16 release](https://github.com/kljensen/psql-static/releases/tag/pg16)
> for the current filename.

## Supported versions & architectures

| PostgreSQL major | Architectures      |
|------------------|--------------------|
| 15               | x86_64, aarch64    |
| 16               | x86_64, aarch64    |
| 17               | x86_64, aarch64    |
| 18               | x86_64, aarch64    |

Binaries are rebuilt automatically every Monday and whenever a new patch version
is detected on [ftp.postgresql.org](https://ftp.postgresql.org/pub/source/).

## Features

- **Fully static** — no `libc.so`, no `libssl.so`, no `libreadline.so`
- **SSL/TLS support** — connects to servers that require SSL (e.g. Crunchy Bridge,
  Amazon RDS, etc.)
- **readline** — tab completion and command history work out of the box
- **`.pgpass` and `.pg_service.conf`** — standard client config files honoured
- **Small** — ~5 MB stripped

## Build locally

You need Docker with buildx support (or [OrbStack](https://orbstack.dev)).

```bash
# Build for your local platform
docker buildx build \
  --build-arg PG_VERSION=16.13 \
  --output type=local,dest=./out \
  .
./out/psql --version

# Cross-build for a specific platform
docker buildx build \
  --platform linux/arm64 \
  --build-arg PG_VERSION=16.13 \
  --output type=local,dest=./out \
  .
```

## How the build works

PostgreSQL's build system has a subtlety: passing `LDFLAGS="-static"` globally
during `./configure` causes the `libpq.so` build to fail with a `crtbeginT.o`
relocation error (the static startup object cannot be used in a shared object).

The workaround used here:

1. `./configure` runs **without** `-static` so `libpq.so` builds cleanly
2. The libraries (`libpq`, `libpgcommon`, `libpgport`, `libpgfeutils`) are built
   as usual, producing both `.a` and `.so` variants
3. A **manual re-link** of the final `psql` binary passes `-static` and the
   correct library order (`-lreadline -lncurses` — configure omits `-lncurses`
   because readline finds it dynamically, but static linking requires it
   explicitly)

## CI / release strategy

The [release workflow](.github/workflows/release.yml):

- Queries `ftp.postgresql.org` to find the **latest patch** for each supported
  major (so no manual version bumps needed)
- Runs a **matrix** of `(pg_version × arch)` jobs in parallel using GitHub's
  native runners (`ubuntu-latest` for x86_64, `ubuntu-24.04-arm` for aarch64)
- Publishes **one release per major** (`pg15`, `pg16`, `pg17`, `pg18`), each
  updated in-place when a new patch ships

## License

The build scripts and Dockerfile in this repo are MIT licensed.
PostgreSQL itself is released under the [PostgreSQL License](https://www.postgresql.org/about/licence/).
