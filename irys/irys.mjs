#!/usr/bin/env node
// Irys SDK runner — fund / price / balance / upload.
// Replaces the legacy interactive @irys/cli (which hangs on its Y/N prompt in
// non-TTY Docker). All operations here are fully programmatic and non-interactive.
//
// Config comes from environment variables (see entrypoint.sh / README):
//   COMMAND       fund | price | balance | upload   (also argv[2])
//   EVM_KEY_FILE  path to hex private key (with or without 0x)
//   IRYS_NODE     mainnet | devnet                  (default: mainnet)
//   IRYS_TOKEN    matic | ethereum | bnb | ...      (default: matic)
//   IRYS_RPC      optional custom RPC URL
//   AMOUNT        atomic units to fund (fund only)
//   TARGET_FILE   .age file to price/upload
//   ADDRESS       optional address to query (balance only; defaults to wallet)

import { readFileSync, statSync } from "node:fs";
import { Uploader } from "@irys/upload";
import {
  Ethereum,
  Matic,
  BNB,
  Avalanche,
  Arbitrum,
  BaseEth,
} from "@irys/upload-ethereum";

const TOKENS = {
  matic: Matic,
  polygon: Matic,
  ethereum: Ethereum,
  eth: Ethereum,
  bnb: BNB,
  avalanche: Avalanche,
  arbitrum: Arbitrum,
  base: BaseEth,
};

// Default RPCs per token. The Irys SDK's own default for Matic (polygon-rpc.com)
// is frequently rate-limited/disabled (HTTP 403), which makes funding hang — so
// we ship a working public default for Polygon. Override with IRYS_RPC.
const DEFAULT_RPC = {
  matic: "https://polygon.drpc.org",
  polygon: "https://polygon.drpc.org",
  ethereum: "https://eth.drpc.org",
  eth: "https://eth.drpc.org",
  bnb: "https://bsc.drpc.org",
};

const command = process.argv[2] || process.env.COMMAND || "help";
const node = process.env.IRYS_NODE || "mainnet";
const tokenName = (process.env.IRYS_TOKEN || "matic").toLowerCase();
const rpc = process.env.IRYS_RPC || DEFAULT_RPC[tokenName] || "";
const keyFile = process.env.EVM_KEY_FILE || "/keys/evm_pk.txt";

function die(msg) {
  console.error(`ERROR: ${msg}`);
  process.exit(1);
}

function readWalletKey() {
  let key;
  try {
    key = readFileSync(keyFile, "utf8").trim();
  } catch {
    die(`EVM_KEY_FILE '${keyFile}' not found. Put your hex private key (with or without 0x) there.`);
  }
  if (!key) die(`EVM_KEY_FILE '${keyFile}' is empty.`);
  return key.startsWith("0x") ? key : `0x${key}`;
}

async function getUploader() {
  const Token = TOKENS[tokenName];
  if (!Token) {
    die(`unsupported IRYS_TOKEN '${tokenName}'. Supported: ${Object.keys(TOKENS).join(", ")}`);
  }
  let builder = Uploader(Token).withWallet(readWalletKey());
  if (rpc) builder = builder.withRpc(rpc);
  if (node === "devnet") builder = builder.devnet();
  return builder; // thenable builder resolves to a ready Irys instance
}

async function main() {
  switch (command) {
    case "fund": {
      const amount = process.env.AMOUNT;
      if (!amount) die("AMOUNT env var is required (atomic units, e.g. 500000000000000000 = 0.5 MATIC)");
      const irys = await getUploader();
      console.log(`Wallet:  ${irys.address}`);
      console.log(`Funding Irys (${node}, ${tokenName}) with ${amount} atomic units...`);
      const receipt = await irys.fund(amount);
      console.log(`Funded ${irys.utils.fromAtomic(receipt.quantity)} ${tokenName} (tx ${receipt.id})`);
      break;
    }

    case "price": {
      const file = process.env.TARGET_FILE;
      if (!file) die("TARGET_FILE env var is required");
      const size = statSync(file).size;
      const irys = await getUploader();
      const atomic = await irys.getPrice(size);
      console.log(`File:  ${file} (${size} bytes)`);
      console.log(`Price: ${atomic} atomic units (${irys.utils.fromAtomic(atomic)} ${tokenName})`);
      break;
    }

    case "balance": {
      const irys = await getUploader();
      const address = process.env.ADDRESS || irys.address;
      const atomic = await irys.getBalance(address);
      console.log(`Address: ${address}`);
      console.log(`Balance: ${atomic} atomic units (${irys.utils.fromAtomic(atomic)} ${tokenName})`);
      break;
    }

    case "upload": {
      const file = process.env.TARGET_FILE;
      if (!file) die("TARGET_FILE env var is required");
      const irys = await getUploader();
      console.log(`Uploading ${file} to Arweave via Irys (${node}, ${tokenName})...`);
      const receipt = await irys.uploadFile(file);
      console.log(`Done. Transaction ID: ${receipt.id}`);
      console.log(`URL: https://gateway.irys.xyz/${receipt.id}`);
      break;
    }

    default:
      console.error(`Unknown command '${command}'. Use: fund | price | balance | upload`);
      process.exit(1);
  }
}

main().catch((e) => {
  console.error(`ERROR: ${e?.message ?? e}`);
  process.exit(1);
});
