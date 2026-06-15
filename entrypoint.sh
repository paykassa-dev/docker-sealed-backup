#!/bin/bash
set -euo pipefail

COMMAND="${1:-${COMMAND:-help}}"

KEY_FILE="${KEY_FILE:-/keys/key.txt}"
ZSTD_LEVEL="${ZSTD_LEVEL:-3}"
THREADS="${THREADS:-0}"
INPUT_DIR="${INPUT_DIR:-/data}"
OUTPUT_FILE="${OUTPUT_FILE:-/output/backup.tar.zst.age}"
TARGET_FILE="${TARGET_FILE:-/input/backup.tar.zst.age}"
DECRYPT_DIR="${DECRYPT_DIR:-/output}"

IRYS_NODE="${IRYS_NODE:-mainnet}"
IRYS_TOKEN="${IRYS_TOKEN:-matic}"
EVM_KEY_FILE="${EVM_KEY_FILE:-/keys/evm_pk.txt}"

# Guard: abort upload of anything that is not a valid age-encrypted file.
# Checks both the .age extension and the age binary header.
_assert_encrypted() {
  local file="$1"
  case "$file" in
    *.age) ;;
    *)
      echo "ERROR: '$file' must have .age extension — only encrypted archives may be uploaded." >&2
      exit 1
      ;;
  esac
  if [ ! -f "$file" ]; then
    echo "ERROR: file not found: $file" >&2
    exit 1
  fi
  if ! head -c 23 "$file" | grep -qF "age-encryption.org"; then
    echo "ERROR: '$file' is missing the age header — this file does not appear to be age-encrypted. Upload aborted." >&2
    exit 1
  fi
}

_require_evm_key() {
  if [ ! -f "$EVM_KEY_FILE" ]; then
    echo "ERROR: EVM_KEY_FILE '$EVM_KEY_FILE' not found." >&2
    echo "       Put your hex private key (without 0x) into that file or set EVM_KEY_FILE." >&2
    exit 1
  fi
}

case "$COMMAND" in
  keygen)
    mkdir -p "$(dirname "$KEY_FILE")"
    age-keygen -o "$KEY_FILE"
    echo ""
    echo "Public key (use as PUB_KEY for encrypt):"
    grep "^# public key:" "$KEY_FILE" | awk '{print $NF}'
    ;;

  encrypt)
    if [ -z "${PUB_KEY:-}" ]; then
      echo "ERROR: PUB_KEY env var is required" >&2
      exit 1
    fi
    if [ ! -d "$INPUT_DIR" ]; then
      echo "ERROR: INPUT_DIR '$INPUT_DIR' not found or not mounted" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    echo "Compressing (zstd level ${ZSTD_LEVEL}, threads ${THREADS}) and encrypting..."
    tar -cf - -C "$INPUT_DIR" . \
      | zstd -T"$THREADS" -"$ZSTD_LEVEL" \
      | age -r "$PUB_KEY" > "$OUTPUT_FILE"
    echo "Done: $OUTPUT_FILE"
    ;;

  decrypt)
    if [ ! -f "$TARGET_FILE" ]; then
      echo "ERROR: TARGET_FILE '$TARGET_FILE' not found or not mounted" >&2
      exit 1
    fi
    if [ ! -f "$KEY_FILE" ]; then
      echo "ERROR: KEY_FILE '$KEY_FILE' not found or not mounted" >&2
      exit 1
    fi
    mkdir -p "$DECRYPT_DIR"
    echo "Decrypting and decompressing..."
    age -d -i "$KEY_FILE" "$TARGET_FILE" \
      | zstd -d \
      | tar -xf - -C "$DECRYPT_DIR"
    echo "Done: $DECRYPT_DIR"
    ;;

  balance)
    if [ -z "${ADDRESS:-}" ]; then
      echo "ERROR: ADDRESS env var is required (the 0x... EVM address printed during fund/keygen)" >&2
      exit 1
    fi
    echo "Irys node balance for ${ADDRESS} (${IRYS_NODE}, ${IRYS_TOKEN}):"
    irys balance "$ADDRESS" -n "$IRYS_NODE" -t "$IRYS_TOKEN"
    ;;

  price)
    _assert_encrypted "$TARGET_FILE"
    SIZE=$(wc -c < "$TARGET_FILE" | awk '{print $1}')
    echo "Checking upload price for: $TARGET_FILE (${SIZE} bytes)"
    irys price "$SIZE" -n "$IRYS_NODE" -t "$IRYS_TOKEN"
    ;;

  fund)
    if [ -z "${AMOUNT:-}" ]; then
      echo "ERROR: AMOUNT env var is required (atomic units, e.g. 500000000000000000 = 0.5 MATIC)" >&2
      exit 1
    fi
    _require_evm_key
    echo "Funding Irys node (${IRYS_NODE}) with ${AMOUNT} atomic units of ${IRYS_TOKEN}..."
    irys fund "$AMOUNT" -n "$IRYS_NODE" -t "$IRYS_TOKEN" -w "$(cat "$EVM_KEY_FILE")"
    ;;

  upload)
    _assert_encrypted "$TARGET_FILE"
    _require_evm_key
    echo "Uploading $TARGET_FILE to Arweave via Irys (${IRYS_NODE}, token: ${IRYS_TOKEN})..."
    irys upload "$TARGET_FILE" -n "$IRYS_NODE" -t "$IRYS_TOKEN" -w "$(cat "$EVM_KEY_FILE")"
    ;;

  help|*)
    cat <<EOF
Usage: docker run [env flags] <image> <command>

Commands:
  keygen   Generate an age key pair and save to KEY_FILE
  encrypt  Compress INPUT_DIR and encrypt to OUTPUT_FILE
  decrypt  Decrypt TARGET_FILE and extract to DECRYPT_DIR
  price    Show Irys upload cost for TARGET_FILE (must be .age)
  fund     Fund the Irys node balance (requires AMOUNT and EVM_KEY_FILE)
  balance  Show current Irys node balance (requires ADDRESS)
  upload   Upload TARGET_FILE to Arweave via Irys (must be .age)

Crypto / compression:
  PUB_KEY       Age recipient public key (required for encrypt)
  KEY_FILE      Path to private key file   (default: /keys/key.txt)
  ZSTD_LEVEL    Compression level 1-22     (default: 3)
  THREADS       zstd threads, 0=auto       (default: 0)
  INPUT_DIR     Directory to compress      (default: /data)
  OUTPUT_FILE   Encrypted output path      (default: /output/backup.tar.zst.age)
  TARGET_FILE   Encrypted file to act on   (default: /input/backup.tar.zst.age)
  DECRYPT_DIR   Extraction directory       (default: /output)

Irys / Arweave:
  IRYS_NODE     Irys network: mainnet or devnet  (default: mainnet)
  IRYS_TOKEN    Payment token                    (default: matic)
  EVM_KEY_FILE  Path to EVM private key file     (default: /keys/evm_pk.txt)
  AMOUNT        Atomic units to fund (e.g. 500000000000000000 = 0.5 MATIC)
  ADDRESS       EVM wallet address for balance check (0x...)

Volumes to mount:
  keygen:  /keys                      (rw)
  encrypt: /data (ro), /output (rw)
  decrypt: /input (ro), /output (rw), /keys (ro)
  price:   /input (ro)
  fund:    /keys (ro)
  upload:  /input (ro), /keys (ro)
EOF
    ;;
esac
