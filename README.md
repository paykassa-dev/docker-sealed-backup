# docker-sealed-backup

Compress, encrypt, and permanently archive directories to Arweave via a single pipeline.

```
tar → zstd (compression) → age (encryption) → Irys → Arweave
```

Packaged as a self-contained Docker image — no local tooling required.

```bash
docker pull ghcr.io/paykassa-dev/docker-sealed-backup:latest
```

> **RPC endpoints:** the image ships working public defaults per token
> (Polygon → `polygon.drpc.org`, Ethereum → `eth.drpc.org`, BNB → `bsc.drpc.org`),
> because the Irys SDK's own default (`polygon-rpc.com`) is frequently rate-limited and
> makes funding hang. For heavy use, pass your own dedicated endpoint via `IRYS_RPC`.

## Quick start

```bash
# 1. Generate age key pair (prints public key)
docker run --rm \
  -v "$(pwd)/keys":/keys \
  ghcr.io/paykassa-dev/docker-sealed-backup keygen

# 2. Encrypt a directory
docker run --rm \
  -v "$(pwd)/photos":/data:ro \
  -v "$(pwd)/encrypted":/output \
  -e PUB_KEY="age1..." \
  ghcr.io/paykassa-dev/docker-sealed-backup encrypt

# 3. Check upload cost
docker run --rm \
  -v "$(pwd)/encrypted":/input:ro \
  -v "$(pwd)/keys":/keys:ro \
  ghcr.io/paykassa-dev/docker-sealed-backup price

# 4. Fund your Irys balance (0.5 MATIC = 500000000000000000 atomic units)
docker run --rm \
  -v "$(pwd)/keys":/keys:ro \
  -e AMOUNT="500000000000000000" \
  ghcr.io/paykassa-dev/docker-sealed-backup fund

# 5. Check funded balance
docker run --rm \
  -v "$(pwd)/keys":/keys:ro \
  ghcr.io/paykassa-dev/docker-sealed-backup balance

# 6. Upload to Arweave
docker run --rm \
  -v "$(pwd)/encrypted":/input:ro \
  -v "$(pwd)/keys":/keys:ro \
  ghcr.io/paykassa-dev/docker-sealed-backup upload

# 7. Decrypt (any time, from anyone with the private key)
docker run --rm \
  -v "$(pwd)/encrypted":/input:ro \
  -v "$(pwd)/restored":/output \
  -v "$(pwd)/keys":/keys:ro \
  ghcr.io/paykassa-dev/docker-sealed-backup decrypt
```

## Commands

| Command   | Description                                                     |
|-----------|-----------------------------------------------------------------|
| `keygen`  | Generate an age key pair, save private key to `KEY_FILE`        |
| `encrypt` | Compress `INPUT_DIR` with zstd and encrypt with age             |
| `decrypt` | Decrypt and decompress to `DECRYPT_DIR`                         |
| `price`   | Show Irys upload cost for `TARGET_FILE` (must be `.age`)        |
| `fund`    | Fund the Irys node balance                                      |
| `balance` | Show current funded Irys node balance                          |
| `upload`  | Upload `TARGET_FILE` to Arweave via Irys (must be `.age`)       |
| `help`    | Print usage (default)                                           |

## Environment variables

### Crypto / compression

| Variable      | Default                       | Description                              |
|---------------|-------------------------------|------------------------------------------|
| `PUB_KEY`     | —                             | Age recipient public key (**required for encrypt**) |
| `KEY_FILE`    | `/keys/key.txt`               | Path to age private key inside container |
| `ZSTD_LEVEL`  | `3`                           | Compression level `1`–`22`              |
| `THREADS`     | `0` (auto)                    | zstd worker threads                      |
| `INPUT_DIR`   | `/data`                       | Source directory to compress             |
| `OUTPUT_FILE` | `/output/backup.tar.zst.age`  | Encrypted output file path               |
| `TARGET_FILE` | `/input/backup.tar.zst.age`   | Encrypted file to decrypt/upload         |
| `DECRYPT_DIR` | `/output`                     | Extraction target directory              |

### Irys / Arweave

Uses the [`@irys/upload`](https://www.npmjs.com/package/@irys/upload) SDK (non-interactive).

| Variable       | Default              | Description                                      |
|----------------|----------------------|--------------------------------------------------|
| `IRYS_NODE`    | `mainnet`            | Irys network (`mainnet` or `devnet`)             |
| `IRYS_TOKEN`   | `matic`              | Payment token (`matic`, `ethereum`, `bnb`, …)    |
| `IRYS_RPC`     | per-token default    | Custom RPC URL (defaults: drpc.org per token — see note above) |
| `EVM_KEY_FILE` | `/keys/evm_pk.txt`   | EVM private key file, hex (needed for fund/price/balance/upload) |
| `AMOUNT`       | —                    | Atomic units to fund (**required for `fund`**)   |
| `ADDRESS`      | own wallet           | Address to query for `balance` (optional)        |

## Upload safety guard

`upload` and `price` refuse to run if `TARGET_FILE`:

- does not end with `.age`, **or**
- does not contain the `age-encryption.org` binary header

This prevents unencrypted data from ever reaching the network.

## Irys funding

Irys uses a pre-pay model: you fund your per-node balance once, then spend it on uploads.  
The `AMOUNT` must be in atomic units (smallest denomination of the token):

| MATIC | Atomic units             |
|-------|--------------------------|
| 0.1   | `100000000000000000`     |
| 0.5   | `500000000000000000`     |
| 1.0   | `1000000000000000000`    |

Run `price` first to see the exact cost, then `fund` with that amount.

After a successful `upload`, Irys prints a transaction URL:
```
https://gateway.irys.xyz/<tx_id>
```
The file is then permanently available on Arweave at that URL.

## Volume mounts

| Command   | Mount                              | Mode                       |
|-----------|------------------------------------|----------------------------|
| `keygen`  | `/keys`                            | `rw`                       |
| `encrypt` | `/data`, `/output`                 | `/data` is `ro`            |
| `decrypt` | `/input`, `/output`, `/keys`       | `/input`, `/keys` are `ro` |
| `price`   | `/input`, `/keys`                  | both `ro`                  |
| `fund`    | `/keys`                            | `ro`                       |
| `balance` | `/keys`                            | `ro`                       |
| `upload`  | `/input`, `/keys`                  | both `ro`                  |

## Compression levels

| Level  | Profile            |
|--------|--------------------|
| 1–3    | Fast, daily use    |
| 9–12   | Balanced           |
| 19–22  | Maximum, slow      |

## Using the Makefile

```bash
# native (requires age + zstd locally, and: cd irys && npm install)
make age-keygen
make compress-crypt   SRC_DIR=./photos PUB_KEY=age1... ZSTD_LEVEL=9
make irys-price
make irys-fund        AMOUNT=500000000000000000
make irys-balance
make irys-upload

# docker
make docker-build
make docker-keygen
make docker-encrypt   SRC_DIR=./photos PUB_KEY=age1... ZSTD_LEVEL=9
make docker-price
make docker-fund      AMOUNT=500000000000000000
make docker-balance
make docker-upload
make docker-decrypt   DECRYPT_DIR=./restored
```

## docker-compose example

```yaml
services:
  encrypt:
    image: ghcr.io/paykassa-dev/docker-sealed-backup:latest
    command: encrypt
    environment:
      PUB_KEY: "age1..."
      ZSTD_LEVEL: "9"
    volumes:
      - ./data:/data:ro
      - ./encrypted:/output

  upload:
    image: ghcr.io/paykassa-dev/docker-sealed-backup:latest
    command: upload
    environment:
      IRYS_TOKEN: matic
    volumes:
      - ./encrypted:/input:ro
      - ./keys:/keys:ro
```

## Security notes

- The age private key and EVM private key are never copied into the image.
- Mount `/keys` as read-only (`ro`) for all operations except `keygen`.
- Keep `keys/` out of version control — it is listed in `.gitignore`.
- `upload` validates the age header before sending any bytes to the network.

## License

MIT
