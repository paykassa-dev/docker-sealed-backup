# Developer guide

## Prerequisites

| Tool     | Install                                      |
|----------|----------------------------------------------|
| Docker   | https://docs.docker.com/get-docker/          |
| age      | `brew install age` / `apk add age`           |
| zstd     | `brew install zstd` / `apk add zstd`         |
| Node.js  | `brew install node` / `apk add nodejs npm`   |
| irys CLI | `npm install -g @irys/cli@0.0.19`            |
| GNU make | bundled on Linux, `brew install make` on mac |

## Project structure

```
.
├── Dockerfile        # Alpine image: age + zstd + nodejs + @irys/cli
├── entrypoint.sh     # Command dispatcher (keygen/encrypt/decrypt/price/fund/upload)
├── Makefile          # Native and docker targets
├── README.md         # End-user image documentation
├── DEV.md            # This file
├── test_data/        # Sample files for manual testing — gitignored
├── keys/             # age and EVM keys — gitignored, NEVER commit
├── crypted/          # Encrypted output — gitignored
└── decrypt/          # Decrypted output — gitignored
```

## Build the image

```bash
make docker-build IMAGE=ghcr.io/paykassa-dev/docker-sealed-backup:latest
```

The image includes `age`, `zstd`, `nodejs`, and `@irys/cli@0.0.19`.  
It is larger than the previous crypto-only image (~300 MB vs ~10 MB) due to Node.js.

## Wallet setup (EVM / Polygon)

1. Create or use an existing EVM wallet with some MATIC on Polygon mainnet.
2. Export the private key as a hex string (no `0x` prefix).
3. Save it to `keys/evm_pk.txt`:
   ```
   abcdef1234...   ← raw hex, single line, no 0x
   ```
4. The file is already excluded from git via `keys/` in `.gitignore`.

To use devnet for testing (free test tokens):
```bash
make docker-fund IRYS_NODE=devnet AMOUNT=1000000000000000000
```

## Run the full pipeline locally (native, no Docker)

```bash
make age-keygen
make compress-crypt     SRC_DIR=./test_data ZSTD_LEVEL=3
make decompress-decrypt
diff -r test_data decrypt/   # should be empty

# Arweave upload (requires irys CLI and funded wallet)
make irys-price
make irys-fund  AMOUNT=500000000000000000
make irys-upload
```

## Run the full pipeline via Docker

```bash
make docker-build
make docker-keygen

# copy the printed public key, then:
make docker-encrypt SRC_DIR=./test_data PUB_KEY=age1...
make docker-price
make docker-fund    AMOUNT=500000000000000000
make docker-upload
make docker-decrypt
diff -r test_data decrypt/   # should be empty
```

## Test the upload safety guard

The upload commands must reject anything that is not a valid age file:

```bash
# Should fail — wrong extension
TARGET_FILE=./crypted/backup.tar.zst make irys-upload

# Should fail — .age extension but not actually encrypted
echo "hello" > /tmp/fake.age
TARGET_FILE=/tmp/fake.age make irys-upload
```

Both should exit non-zero with a clear error message.

## Test compression levels

```bash
for level in 1 3 9 19; do
  make compress-crypt ZSTD_LEVEL=$level PUB_KEY=age1... && \
  ls -lh crypted/backup.tar.zst.age
done
```

## Publish the image

```bash
IMAGE=ghcr.io/<your-org>/docker-sealed-backup

docker build -t $IMAGE:latest .
docker push $IMAGE:latest

docker tag $IMAGE:latest $IMAGE:1.0.0
docker push $IMAGE:1.0.0
```

## Overriding Makefile variables

All variables can be overridden on the command line:

```bash
make docker-encrypt \
  IMAGE=ghcr.io/paykassa-dev/docker-sealed-backup:latest \
  SRC_DIR=/Volumes/backup/documents \
  CRYPTED_DIR=/Volumes/nas/encrypted \
  PUB_KEY=age1... \
  ZSTD_LEVEL=9 \
  THREADS=4

make docker-upload \
  CRYPTED_DIR=/Volumes/nas/encrypted \
  IRYS_TOKEN=matic \
  IRYS_NODE=mainnet
```

## entrypoint.sh conventions

- All paths come from env vars with sane defaults.
- Strict mode: `set -euo pipefail` — any failure exits non-zero.
- `_assert_encrypted` guards `price`, `fund`, and `upload` — checks both `.age` extension and the `age-encryption.org` binary header. Call it at the top of any new command that touches external networks.
- `_require_evm_key` validates the EVM key file exists before use.
- Adding a new command: add a `case` branch, call the appropriate guards, document env vars used.

## Dockerfile notes

- Base image pinned by digest (`alpine:3.24.0@sha256:...`) for reproducibility.
- `@irys/cli` pinned to `0.0.19`. To upgrade: update both the Dockerfile and this file.
- No secrets, keys, or data are baked into the image.
