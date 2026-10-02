#!/usr/bin/env node
// 署名と manifest を、rulestool（CryptoKit）とは別の実装で検証する。
// Node の標準の crypto（OpenSSL）だけを使い、npm のパッケージは使わない。
//
// アプリと同じ順番で確かめる：
//   1. manifest.json のバイト列のまま、署名（Ed25519、Base64）を検証する
//   2. 検証できてから JSON として読み、docs/format.md の取り決めに合っているかを見る
//   3. 各リストの size・sha256・JSON の配列か・rule_count
//
// 使い方：node .github/scripts/verify-manifest.mjs --dir <build/out か dist> [--keys keys/trusted-public-keys.json]
// 終了コード：0 = 検証できた、1 = 検証できない、2 = 使い方の誤り

import { createHash, createPublicKey, verify } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

// Ed25519 の公開鍵（32 バイト）の前に付ける SPKI（DER）の固定の頭（RFC 8410）
const SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
// docs/format.md のカテゴリ。lists はこの順に並ぶ（Sources/RulesKit/Basics.swift の RuleCategory と同じ）
const CATEGORIES = ["basic", "annoyance", "privacy", "scam"];
const FILE_SIZE_LIMIT = 25 * 1024 * 1024;
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

function usage(message) {
  console.error(message);
  console.error("使い方：node .github/scripts/verify-manifest.mjs --dir <dir> [--keys <path>]");
  process.exit(2);
}

function fail(message) {
  console.error(`✘ ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { keys: "keys/trusted-public-keys.json" };
  for (let i = 0; i < argv.length; i += 1) {
    const name = argv[i];
    const value = argv[i + 1];
    if ((name === "--dir" || name === "--keys") && value !== undefined) {
      args[name.slice(2)] = value;
      i += 1;
    } else {
      usage(`知らない引数です：${name}`);
    }
  }
  if (!args.dir) usage("--dir を指定してください");
  return args;
}

function decodeBase64(text, expectedBytes, label) {
  const trimmed = text.trim();
  if (!BASE64.test(trimmed)) fail(`${label} が Base64 ではありません`);
  const bytes = Buffer.from(trimmed, "base64");
  if (bytes.length !== expectedBytes) {
    fail(`${label} の長さが ${bytes.length} バイトです（${expectedBytes} バイトのはず）`);
  }
  return bytes;
}

function loadTrustedKeys(path) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    fail(`${path} を読めません（${e.message}）`);
  }
  if (!Array.isArray(parsed.keys) || parsed.keys.length === 0) {
    fail(`${path} に公開鍵がありません（docs/signing.md の手順で登録してください）`);
  }
  return parsed.keys.map((entry, index) => {
    const id = typeof entry.id === "string" ? entry.id : `#${index}`;
    const raw = decodeBase64(String(entry.publicKey ?? ""), 32, `公開鍵 ${id}`);
    const key = createPublicKey({ key: Buffer.concat([SPKI_PREFIX, raw]), format: "der", type: "spki" });
    return { id, key };
  });
}

function isInteger(value, min) {
  return Number.isInteger(value) && value >= min;
}

function checkManifest(manifest) {
  const problems = [];
  if (manifest.schema !== 1) problems.push(`schema が 1 ではありません（${manifest.schema}）`);
  if (typeof manifest.version !== "string" || !/^\d{4}\.\d{2}\.\d{2}\.[1-9]\d*$/.test(manifest.version)) {
    problems.push(`version が YYYY.MM.DD.N の形ではありません（${manifest.version}）`);
  }
  if (typeof manifest.published_at !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(manifest.published_at)) {
    problems.push(`published_at が RFC 3339 の UTC（秒まで）ではありません（${manifest.published_at}）`);
  }
  if (!isInteger(manifest.min_app_build, 1)) problems.push(`min_app_build が 1 以上の整数ではありません（${manifest.min_app_build}）`);
  if (!Array.isArray(manifest.lists) || manifest.lists.length === 0) {
    problems.push("lists が空です");
    return problems;
  }
  const seen = new Set();
  let previousOrder = -1;
  for (const entry of manifest.lists) {
    const label = `lists[${entry.category}]`;
    const order = CATEGORIES.indexOf(entry.category);
    if (order < 0) {
      problems.push(`${label}：知らないカテゴリです`);
    } else {
      if (order < previousOrder) problems.push(`${label}：lists が ${CATEGORIES.join("・")} の順に並んでいません`);
      previousOrder = order;
    }
    if (seen.has(entry.category)) problems.push(`${label}：同じカテゴリが 2 回あります`);
    seen.add(entry.category);
    if (typeof entry.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(entry.sha256)) {
      problems.push(`${label}：sha256 が 64 文字の小文字の 16 進ではありません`);
    }
    const match = /^lists\/([a-z]+)\.([0-9a-f]{8})\.json$/.exec(entry.url ?? "");
    if (!match) {
      problems.push(`${label}：url が lists/<category>.<hash8>.json の形ではありません（${entry.url}）`);
    } else if (match[1] !== entry.category || match[2] !== String(entry.sha256).slice(0, 8)) {
      problems.push(`${label}：url のカテゴリかハッシュが、category・sha256 と合いません（${entry.url}）`);
    }
    if (!isInteger(entry.size, 1) || entry.size >= FILE_SIZE_LIMIT) problems.push(`${label}：size が 1 以上 25 MiB 未満ではありません（${entry.size}）`);
    if (!isInteger(entry.rule_count, 1)) problems.push(`${label}：rule_count が 1 以上の整数ではありません（${entry.rule_count}）`);
  }
  return problems;
}

function checkList(baseDir, entry) {
  const path = join(baseDir, entry.url);
  if (!existsSync(path)) return `${entry.url} がありません`;
  const data = readFileSync(path);
  if (data.length !== entry.size) return `大きさが ${data.length} バイトです（manifest では ${entry.size}）`;
  const hash = createHash("sha256").update(data).digest("hex");
  if (hash !== entry.sha256) return `SHA-256 が合いません（${hash}）`;
  let rules;
  try {
    rules = JSON.parse(data.toString("utf8"));
  } catch (e) {
    return `JSON として読めません（${e.message}）`;
  }
  if (!Array.isArray(rules) || rules.length === 0) return "空でない JSON の配列ではありません";
  if (!rules.every((rule) => rule !== null && typeof rule === "object" && !Array.isArray(rule))) {
    return "配列の要素にオブジェクトでないものがあります";
  }
  if (rules.length !== entry.rule_count) return `ルールが ${rules.length} 件です（manifest では ${entry.rule_count}）`;
  return null;
}

const args = parseArgs(process.argv.slice(2));
let manifestPath = join(args.dir, "v1", "manifest.json");
if (!existsSync(manifestPath) && existsSync(join(args.dir, "manifest.json"))) {
  manifestPath = join(args.dir, "manifest.json");
}
if (!existsSync(manifestPath)) fail(`${manifestPath} がありません`);
const signaturePath = `${manifestPath}.sig`;
if (!existsSync(signaturePath)) fail(`${signaturePath} がありません（署名していません）`);

// 1. 署名（バイト列のまま）
const manifestBytes = readFileSync(manifestPath);
const signature = decodeBase64(readFileSync(signaturePath, "utf8"), 64, "manifest.json.sig");
const trusted = loadTrustedKeys(args.keys);
const signer = trusted.find(({ key }) => verify(null, manifestBytes, key, signature));
if (!signer) fail(`署名を検証できません（${args.keys} のどの公開鍵でも合いません）`);
console.log(`✔ 署名：公開鍵「${signer.id}」で検証できました（Node ${process.version}、OpenSSL ${process.versions.openssl}）`);

// 2. manifest の中身（署名の検証のあとで読む）
let manifest;
try {
  manifest = JSON.parse(manifestBytes.toString("utf8"));
} catch (e) {
  fail(`manifest.json を JSON として読めません（${e.message}）`);
}
const problems = checkManifest(manifest);
if (problems.length > 0) fail(`manifest.json が取り決めに合っていません：\n  - ${problems.join("\n  - ")}`);
console.log(`✔ manifest：版 ${manifest.version}（${manifest.published_at}）、min_app_build ${manifest.min_app_build}`);

// 3. 各リスト
const baseDir = dirname(manifestPath);
const listProblems = [];
for (const entry of manifest.lists) {
  const problem = checkList(baseDir, entry);
  if (problem) {
    listProblems.push(`${entry.category}（${entry.url}）：${problem}`);
  } else {
    console.log(`✔ ${entry.category}：${entry.rule_count} 件、${entry.size} バイト`);
  }
}
if (listProblems.length > 0) fail(`リストの検証に失敗しました：\n  - ${listProblems.join("\n  - ")}`);
