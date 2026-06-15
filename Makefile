# ── directories (override on command line or via env) ──────────────────────────
DECRYPT_DIR  := ./decrypt
CRYPTED_DIR  := ./crypted
KEYS_DIR     := ./keys
SRC_DIR      := ./test_data

# ── file paths ─────────────────────────────────────────────────────────────────
TARGET_FILE  := $(CRYPTED_DIR)/backup.tar.zst.age
KEY_FILE     := $(KEYS_DIR)/key.txt

# ── encryption ─────────────────────────────────────────────────────────────────
PUB_KEY      := age1pe9pcx2gw6x48tk3gc38u2usd9fm2ytzsv5r2rcdxdqgs7378qdqrstdul

# ── compression ────────────────────────────────────────────────────────────────
ZSTD_LEVEL   := 3
THREADS      := 0

# ── irys / arweave (via @irys/upload SDK) ────────────────────────────────────────
IRYS_NODE    := mainnet
IRYS_TOKEN   := matic
IRYS_RPC     :=
EVM_KEY_FILE := $(KEYS_DIR)/evm_pk.txt
# AMOUNT is in atomic units: 1 MATIC = 1000000000000000000
AMOUNT       := 500000000000000000
# native runner (requires: cd irys && npm install)
RUNNER       := node irys/irys.mjs
IRYS_ENV     := IRYS_NODE="$(IRYS_NODE)" IRYS_TOKEN="$(IRYS_TOKEN)" IRYS_RPC="$(IRYS_RPC)" EVM_KEY_FILE="$(EVM_KEY_FILE)"

# ── docker ─────────────────────────────────────────────────────────────────────
IMAGE        := ghcr.io/paykassa-dev/docker-sealed-backup:latest

.PHONY: age-keygen compress-crypt decompress-decrypt \
        test_compress_crypt test_decompress_decrypt \
        irys-price irys-fund irys-balance irys-upload \
        docker-build docker-keygen docker-encrypt docker-decrypt \
        docker-price docker-fund docker-upload docker-balance

# ── native targets ─────────────────────────────────────────────────────────────

age-keygen:
	mkdir -p $(KEYS_DIR)
	age-keygen -o $(KEY_FILE)

compress-crypt:
	mkdir -p $(CRYPTED_DIR)
	tar -cvf - $(SRC_DIR) | zstd -T$(THREADS) -$(ZSTD_LEVEL) | age -r $(PUB_KEY) > $(TARGET_FILE)

decompress-decrypt:
	mkdir -p $(DECRYPT_DIR)
	age -d -i $(KEY_FILE) $(TARGET_FILE) | zstd -d | tar -xf - -C $(DECRYPT_DIR)

# backward-compat aliases
test_compress_crypt: compress-crypt
test_decompress_decrypt: decompress-decrypt

# ── native irys targets ────────────────────────────────────────────────────────

irys-price:
	@case "$(TARGET_FILE)" in *.age) ;; *) \
	  echo "ERROR: TARGET_FILE='$(TARGET_FILE)' must end in .age" >&2; exit 1;; esac
	@head -c 23 "$(TARGET_FILE)" | grep -qF "age-encryption.org" || \
	  { echo "ERROR: $(TARGET_FILE) is missing the age header — upload aborted." >&2; exit 1; }
	$(IRYS_ENV) TARGET_FILE="$(TARGET_FILE)" $(RUNNER) price

irys-fund:
	$(IRYS_ENV) AMOUNT="$(AMOUNT)" $(RUNNER) fund

irys-balance:
	$(IRYS_ENV) ADDRESS="$(ADDRESS)" $(RUNNER) balance

irys-upload:
	@case "$(TARGET_FILE)" in *.age) ;; *) \
	  echo "ERROR: TARGET_FILE='$(TARGET_FILE)' must end in .age — only encrypted archives may be uploaded." >&2; exit 1;; esac
	@head -c 23 "$(TARGET_FILE)" | grep -qF "age-encryption.org" || \
	  { echo "ERROR: $(TARGET_FILE) is missing the age header — upload aborted." >&2; exit 1; }
	$(IRYS_ENV) TARGET_FILE="$(TARGET_FILE)" $(RUNNER) upload

# ── docker targets ─────────────────────────────────────────────────────────────

docker-build:
	docker build -t $(IMAGE) .

docker-keygen:
	docker run --rm \
	  -v "$(abspath $(KEYS_DIR))":/keys \
	  $(IMAGE) keygen

docker-encrypt:
	mkdir -p $(CRYPTED_DIR)
	docker run --rm \
	  -v "$(abspath $(SRC_DIR))":/data:ro \
	  -v "$(abspath $(CRYPTED_DIR))":/output \
	  -e PUB_KEY="$(PUB_KEY)" \
	  -e ZSTD_LEVEL="$(ZSTD_LEVEL)" \
	  -e THREADS="$(THREADS)" \
	  $(IMAGE) encrypt

docker-decrypt:
	mkdir -p $(DECRYPT_DIR)
	docker run --rm \
	  -v "$(abspath $(CRYPTED_DIR))":/input:ro \
	  -v "$(abspath $(DECRYPT_DIR))":/output \
	  -v "$(abspath $(KEYS_DIR))":/keys:ro \
	  $(IMAGE) decrypt

docker-price:
	docker run --rm \
	  -v "$(abspath $(CRYPTED_DIR))":/input:ro \
	  -v "$(abspath $(KEYS_DIR))":/keys:ro \
	  -e TARGET_FILE="/input/$(notdir $(TARGET_FILE))" \
	  -e IRYS_NODE="$(IRYS_NODE)" \
	  -e IRYS_TOKEN="$(IRYS_TOKEN)" \
	  -e IRYS_RPC="$(IRYS_RPC)" \
	  $(IMAGE) price

docker-fund:
	docker run --rm \
	  -v "$(abspath $(KEYS_DIR))":/keys:ro \
	  -e AMOUNT="$(AMOUNT)" \
	  -e IRYS_NODE="$(IRYS_NODE)" \
	  -e IRYS_TOKEN="$(IRYS_TOKEN)" \
	  -e IRYS_RPC="$(IRYS_RPC)" \
	  $(IMAGE) fund

docker-balance:
	docker run --rm \
	  -v "$(abspath $(KEYS_DIR))":/keys:ro \
	  -e ADDRESS="$(ADDRESS)" \
	  -e IRYS_NODE="$(IRYS_NODE)" \
	  -e IRYS_TOKEN="$(IRYS_TOKEN)" \
	  -e IRYS_RPC="$(IRYS_RPC)" \
	  $(IMAGE) balance

docker-upload:
	docker run --rm \
	  -v "$(abspath $(CRYPTED_DIR))":/input:ro \
	  -v "$(abspath $(KEYS_DIR))":/keys:ro \
	  -e TARGET_FILE="/input/$(notdir $(TARGET_FILE))" \
	  -e IRYS_NODE="$(IRYS_NODE)" \
	  -e IRYS_TOKEN="$(IRYS_TOKEN)" \
	  -e IRYS_RPC="$(IRYS_RPC)" \
	  $(IMAGE) upload
