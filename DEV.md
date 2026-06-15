# Developer guide

## Prerequisites

| Tool     | Install                                      |
|----------|----------------------------------------------|
| Docker   | https://docs.docker.com/get-docker/          |
| age      | `brew install age` / `apk add age`           |
| zstd     | `brew install zstd` / `apk add zstd`         |
| Node.js  | `brew install node` (≥ 18)                   |
| Irys SDK | `cd irys && npm install` (for native targets)|
| GNU make | bundled on Linux, `brew install make` on mac |

## Project structure

```
.
├── Dockerfile        # Multi-stage Alpine: age + zstd + nodejs + Irys SDK
├── entrypoint.sh     # Command dispatcher (keygen/encrypt/decrypt/price/fund/balance/upload)
├── irys/             # Irys SDK runner (replaces the legacy @irys/cli)
│   ├── irys.mjs      #   programmatic fund/price/balance/upload
│   ├── package.json  #   pinned @irys/upload + @irys/upload-ethereum
│   └── package-lock.json
├── Makefile          # Native and docker targets
├── README.md         # End-user image documentation
├── DEV.md            # This file
├── test_data/        # Sample files for manual testing — gitignored
├── keys/             # age and EVM keys — gitignored, NEVER commit
├── crypted/          # Encrypted output — gitignored
└── decrypt/          # Decrypted output — gitignored
```

## Irys: SDK, not CLI

This project uses the modular **`@irys/upload` + `@irys/upload-ethereum`** SDK via a small
Node runner (`irys/irys.mjs`), **not** the legacy `@irys/cli`. The CLI is interactive
(prompts `Y/N` and crashes on closed stdin in Docker) and bundled with stale native deps.
The SDK path is fully non-interactive and is what the `fund`/`price`/`balance`/`upload`
commands call.

> **Why we override the default RPC.** The SDK's `Matic` token defaults to
> `https://polygon-rpc.com`, which is frequently rate-limited/disabled (HTTP 403); the tx
> then never broadcasts and `fund` hangs. `irys.mjs` ships a `DEFAULT_RPC` map with working
> public endpoints per token (`polygon.drpc.org`, `eth.drpc.org`, `bsc.drpc.org`), overridable
> via `IRYS_RPC`. Verified: `fund 0.005 MATIC` completes in ~35 s using the baked-in default.

## Build the image

```bash
make docker-build IMAGE=ghcr.io/paykassa-dev/docker-sealed-backup:latest
```

Multi-stage build: the `deps` stage compiles the Irys SDK's native modules (needs
`python3 make g++`), then only `node_modules` is copied into the runtime stage (which
carries just `age`, `zstd`, `tar`, `bash`, `nodejs`).

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
make docker-fund IRYS_NODE=devnet AMOUNT=1000000000000000000 IRYS_RPC=https://your-rpc
```

## Run the full pipeline locally (native, no Docker)

```bash
cd irys && npm install && cd ..   # one-time: install the Irys SDK

make age-keygen
make compress-crypt     SRC_DIR=./test_data ZSTD_LEVEL=3
make decompress-decrypt
diff -r test_data decrypt/   # should be empty

# Arweave upload (requires a funded wallet; RPC defaults are built in)
make irys-price
make irys-fund     AMOUNT=500000000000000000
make irys-balance
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
make docker-balance
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
- `_assert_encrypted` guards `price` and `upload` — checks both `.age` extension and the `age-encryption.org` binary header. Call it at the top of any new command that touches external networks.
- `_require_evm_key` validates the EVM key file exists before use.
- Irys commands delegate to `node /opt/irys/irys.mjs <cmd>`; config is passed through exported env vars (`IRYS_NODE`, `IRYS_TOKEN`, `IRYS_RPC`, `EVM_KEY_FILE`, `TARGET_FILE`, `AMOUNT`, `ADDRESS`).
- Adding a new command: add a `case` branch, call the appropriate guards, document env vars used.

## irys/irys.mjs notes

- Token map: `matic`→`Matic`, `ethereum`→`Ethereum`, `bnb`→`BNB`, etc. (from `@irys/upload-ethereum`).
- `DEFAULT_RPC` map provides a working public RPC per token; `IRYS_RPC` overrides it.
- Builder chain: `Uploader(Token).withWallet(pk)[.withRpc(rpc)][.devnet()]`.
- All amounts are atomic units; `utils.fromAtomic()` is used only for display.
- `balance` uses the wallet address derived from the key, unless `ADDRESS` overrides it.

## Dockerfile notes

- Base image pinned by digest (`alpine:3.24.0@sha256:...`) for reproducibility.
- SDK versions pinned in `irys/package.json` + `irys/package-lock.json`; `npm ci` enforces the lock.
- To upgrade the SDK: bump `irys/package.json`, run `npm install --package-lock-only` in `irys/`, rebuild.
- No secrets, keys, or data are baked into the image.
