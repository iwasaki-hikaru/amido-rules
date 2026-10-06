#!/usr/bin/env node
// 配信の設定を検査する（Node の標準機能だけを使う）。
//
// 1. wrangler.jsonc：静的アセットだけの Worker になっているか。アクセスの記録を残さない設定か
//    （main・cache・run_worker_first があると、無料プランでもリクエストが課金の対象になる）
// 2. site/_headers：Cloudflare の制限（100 ルール・1 行 2,000 文字）に収まり、必要なルールがあるか
// 3. site/ の .html（demo/ などのサブディレクトリも）：外部の読み込みや、CSP で止められる書き方（インラインのスクリプト・style 属性など）がないか
// 4. deploy/：wrangler の版が固定されていて、package-lock.json と合っているか
//
// 使い方：node .github/scripts/check-config.mjs（リポジトリのルートで実行する）
// 終了コード：0 = 問題なし、1 = 問題あり

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const inActions = process.env.GITHUB_ACTIONS === "true";
let failures = 0;

function error(file, message) {
  failures += 1;
  if (inActions) {
    console.log(`::error file=${file}::${message}`);
  } else {
    console.error(`✘ ${file}：${message}`);
  }
}

function notice(message) {
  console.log(inActions ? `::notice::${message}` : `・${message}`);
}

// その検査の中で問題がなかったときだけ、確認できたことを表示する
function ok(before, message) {
  if (failures === before) {
    console.log(`✔ ${message}`);
  }
}

// JSONC（コメントと末尾のカンマ）を JSON にする。文字列の中の「//」は残す。
function stripJsonc(text) {
  let out = "";
  let inString = false;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    const next = text[i + 1];
    if (inString) {
      out += c;
      if (c === "\\") {
        out += next ?? "";
        i += 1;
      } else if (c === '"') {
        inString = false;
      }
      continue;
    }
    if (c === '"') {
      inString = true;
      out += c;
    } else if (c === "/" && next === "/") {
      while (i < text.length && text[i] !== "\n") i += 1;
      out += "\n";
    } else if (c === "/" && next === "*") {
      i += 2;
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i += 1;
      i += 1;
    } else {
      out += c;
    }
  }
  return out.replace(/,(\s*[}\]])/g, "$1");
}

function findKeys(value, names, path = "") {
  const found = [];
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      const childPath = path ? `${path}.${key}` : key;
      if (names.includes(key)) found.push(childPath);
      found.push(...findKeys(child, names, childPath));
    }
  }
  return found;
}

// --- 1. wrangler.jsonc ---
function checkWrangler() {
  const before = failures;
  const file = "wrangler.jsonc";
  let config;
  try {
    config = JSON.parse(stripJsonc(readFileSync(file, "utf8")));
  } catch (e) {
    error(file, `読めません（${e.message}）`);
    return;
  }
  const forbidden = findKeys(config, ["main", "cache", "run_worker_first"]);
  if (forbidden.length > 0) {
    error(file, `静的アセットだけにするため、次のキーは使えません：${forbidden.join(", ")}`);
  }
  const expect = [
    ["preview_urls", config.preview_urls, false],
    ["assets.directory", config.assets?.directory, "./dist"],
    ["assets.html_handling", config.assets?.html_handling, "auto-trailing-slash"],
    ["assets.not_found_handling", config.assets?.not_found_handling, "404-page"],
  ];
  for (const [name, actual, expected] of expect) {
    if (actual !== expected) {
      error(file, `${name} は ${JSON.stringify(expected)} にしてください（今は ${JSON.stringify(actual)}）`);
    }
  }
  // アクセスの記録を残さない・送らない（site/privacy.html の 4. に「Workers Logs を無効にし、Logpush なども使わない」と書いている）
  if (config.observability?.enabled !== false) {
    error(file, `observability.enabled は false にしてください（Workers Logs を使わない。今は ${JSON.stringify(config.observability?.enabled)}）`);
  }
  if (config.observability?.logs?.enabled === true) {
    error(file, "observability.logs.enabled を true にしないでください（Workers Logs を使わない）");
  }
  if (config.logpush === true) {
    error(file, "logpush を true にしないでください（記録を外部に転送しない）");
  }
  if (findKeys(config, ["tail_consumers"]).length > 0) {
    error(file, "tail_consumers は使わないでください（記録を別の Worker に渡さない）");
  }
  if (typeof config.compatibility_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(config.compatibility_date)) {
    error(file, "compatibility_date（YYYY-MM-DD）がありません");
  }

  // 配信ホスト（config/distribution.json の host）の形で、合わせるものが変わる
  // - <name>.<サブドメイン>.workers.dev：workers_dev を true にし、name を host の先頭と同じにする
  // - それ以外（カスタムドメイン。例 amido.goalspace.jp）：workers_dev を false にし、route・routes を書かない。
  //   ドメインは Cloudflare の管理画面で Worker につなぐ。CI のトークンはこの Worker だけに絞っていてゾーンの権限がなく、
  //   設定に custom_domain を書くと、wrangler がデプロイのたびにドメインの API を呼ぶ（CI では確認なしに付け替える）ため
  let host;
  try {
    host = JSON.parse(readFileSync("config/distribution.json", "utf8")).host;
  } catch (e) {
    error("config/distribution.json", `読めません（${e.message}）`);
    return;
  }
  const hostname = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$/;
  if (typeof config.name !== "string" || !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(config.name)) {
    error(file, `name は英小文字・数字・ハイフンにしてください（今は ${JSON.stringify(config.name)}）`);
  }
  if (typeof host !== "string" || host === "") {
    error("config/distribution.json", `host がありません（今は ${JSON.stringify(host)}）`);
  } else if (host.includes("PLACEHOLDER")) {
    notice(`配信ホストが仮の値です（${host}）。公開する前に config/distribution.json と wrangler.jsonc を本物にしてください`);
  } else if (!hostname.test(host)) {
    error("config/distribution.json", `host は英小文字のホスト名にしてください（今は ${host}）`);
  } else if (host === "workers.dev" || host.endsWith(".workers.dev")) {
    const labels = host.split(".");
    if (labels.length !== 4) {
      error("config/distribution.json", `workers.dev のときは、host を <Worker 名>.<サブドメイン>.workers.dev の形にしてください（今は ${host}）`);
    } else if (config.name !== labels[0]) {
      error(file, `name（${config.name}）が、config/distribution.json の host の先頭（${labels[0]}）と違います`);
    }
    if (config.workers_dev !== true) {
      error(file, `host が workers.dev なので、workers_dev は true にしてください（今は ${JSON.stringify(config.workers_dev)}）`);
    }
  } else {
    if (config.workers_dev !== false) {
      error(file, `host がカスタムドメインなので、workers_dev は false にしてください（今は ${JSON.stringify(config.workers_dev)}）`);
    }
    const routing = findKeys(config, ["route", "routes"]);
    if (routing.length > 0) {
      error(file, `カスタムドメインは管理画面で Worker につなぎます。${routing.join(", ")} は書かないでください（CI のトークンにゾーンの権限がなく、wrangler がドメインを付け替えるおそれがあるため）`);
    }
  }
  ok(before, `${file}：静的アセットだけの設定です（${host}）`);
}

// --- 2. site/_headers ---
// Cloudflare の解析と同じく、「/」か「https://」で始まる行を URL のパターンとして数える。
function checkHeaders() {
  const before = failures;
  const file = "site/_headers";
  if (!existsSync(file)) {
    error(file, "ありません");
    return;
  }
  const lines = readFileSync(file, "utf8").split("\n");
  const rules = [];
  let current;
  lines.forEach((raw, index) => {
    const line = raw.trim();
    if (line.length === 0 || line.startsWith("#")) return;
    if (line.length > 2000) {
      error(file, `${index + 1} 行目が 2,000 文字を超えています`);
      return;
    }
    if (/^([^\s]+:\/\/|\/)/.test(line)) {
      if ((line.match(/\*/g) ?? []).length > 1) {
        error(file, `${index + 1} 行目：* は 1 つしか使えません`);
      }
      current = { path: line, headers: {} };
      rules.push(current);
      return;
    }
    if (!current) {
      error(file, `${index + 1} 行目：URL のパターンより前にヘッダーがあります`);
      return;
    }
    const at = line.indexOf(":");
    if (at <= 0) {
      error(file, `${index + 1} 行目：「名前: 値」の形ではありません`);
      return;
    }
    current.headers[line.slice(0, at).trim().toLowerCase()] = line.slice(at + 1).trim();
  });
  if (rules.length > 100) {
    error(file, `ルールが ${rules.length} 件あります（上限は 100 件）`);
  }
  for (const rule of rules) {
    if (Object.keys(rule.headers).length === 0) {
      error(file, `${rule.path} にヘッダーがありません`);
    }
  }
  const byPath = Object.fromEntries(rules.map((rule) => [rule.path, rule.headers]));
  const required = [
    ["/*", "content-security-policy", /default-src 'none'/],
    ["/*", "x-content-type-options", /^nosniff$/],
    ["/v1/manifest.json", "cache-control", /max-age=300\b/],
    ["/v1/manifest.json.sig", "content-type", /^text\/plain/],
    ["/v1/manifest.json.sig", "cache-control", /max-age=300\b/],
    ["/v1/lists/*", "cache-control", /immutable/],
  ];
  for (const [path, name, pattern] of required) {
    const value = byPath[path]?.[name];
    if (value === undefined || !pattern.test(value)) {
      error(file, `${path} に ${name}（${pattern}）が必要です`);
    }
  }
  ok(before, `${file}：${rules.length} ルール`);
}

// --- 3. site/ の .html ---
// CSP（default-src 'none'; script-src 'self'; style-src 'self'）の下で動く書き方になっているか。
// site/demo/ の見本のページも配信するので、サブディレクトリの .html も同じように検査する。

// dir の中の .html を、サブディレクトリまで探して、dir からの相対パス（例 "demo/news.html"）で返す
function htmlFiles(dir, prefix = "") {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const relative = prefix + entry.name;
    if (entry.isDirectory()) {
      found.push(...htmlFiles(join(dir, entry.name), `${relative}/`));
    } else if (entry.name.endsWith(".html")) {
      found.push(relative);
    }
  }
  return found;
}

function checkHtml() {
  const before = failures;
  if (existsSync("site/v1")) {
    error("site/v1", "v1/ はツールが作るので、site/ には置かないでください");
  }
  const pages = htmlFiles("site");
  // 必ず要るページは site/ の直下にあるもの
  for (const required of ["index.html", "privacy.html", "terms.html", "support.html", "licenses.html", "check.html", "tokushoho.html", "404.html"]) {
    if (!pages.includes(required)) error(`site/${required}`, "ありません");
  }
  let placeholders = 0;
  for (const name of pages) {
    const file = `site/${name}`;
    const html = readFileSync(file, "utf8");
    const withoutComments = html.replace(/<!--[\s\S]*?-->/g, "");
    placeholders += (withoutComments.match(/【要(記入|確認)/g) ?? []).length;

    if (!/<html lang="ja">/.test(withoutComments)) error(file, '<html lang="ja"> にしてください');
    for (const match of withoutComments.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
      const src = /\bsrc="([^"]*)"/.exec(match[1])?.[1];
      if (!src) {
        error(file, "インラインの <script> は CSP で止められます。assets/ の別ファイルにしてください");
      } else if (!src.startsWith("/") || src.startsWith("//")) {
        error(file, `スクリプトは同じサイトの絶対パス（/assets/…）で読み込んでください：${src}`);
      } else if (!existsSync(join("site", src))) {
        error(file, `${src} がありません`);
      }
    }
    if (/<style\b/i.test(withoutComments)) error(file, "<style> は CSP で止められます。assets/site.css に書いてください");
    if (/\sstyle\s*=/i.test(withoutComments)) error(file, "style 属性は CSP で止められます。クラスを使ってください");
    if (/\son[a-z]+\s*=/i.test(withoutComments)) error(file, "onclick などの属性は CSP で止められます。assets/ のスクリプトで登録してください");
    if (/<(iframe|form|object|embed)\b/i.test(withoutComments)) error(file, "iframe・form・object・embed は使わないでください");
    for (const match of withoutComments.matchAll(/<(link|img|source|video|audio)\b[^>]*\b(href|src|srcset)="([^"]*)"/gi)) {
      const url = match[3];
      if (!url.startsWith("/") || url.startsWith("//")) {
        error(file, `外部や相対パスの読み込みはできません（同じサイトの /… にしてください）：${url}`);
      } else if (!existsSync(join("site", url.split("?")[0]))) {
        error(file, `${url} がありません`);
      }
    }
  }
  const check = readFileSync("site/check.html", "utf8");
  for (const category of ["basic", "annoyance", "privacy"]) {
    const pattern = new RegExp(`id="cb-check-${category}"[^>]*class="[^"]*\\bcb-check-${category}\\b`);
    if (!pattern.test(check)) {
      error("site/check.html", `id と class が cb-check-${category} の枠が必要です（配信するルールがこの枠を隠す）`);
    }
  }
  if (placeholders > 0) {
    // 配信ホストを本物にしたあと（公開できる状態）は、埋め忘れたページを配信しないように失敗にする
    let host = "";
    try {
      host = JSON.parse(readFileSync("config/distribution.json", "utf8")).host ?? "";
    } catch {
      // 読めないことは checkWrangler が報告する
    }
    if (typeof host === "string" && host !== "" && !host.includes("PLACEHOLDER")) {
      error("site/", `「【要記入】」「【要確認】」が ${placeholders} か所残っています。配信ホストが本物なので、埋めてから公開してください`);
    } else {
      notice(`site/ に「【要記入】」「【要確認】」が ${placeholders} か所あります。公開前に埋めてください`);
    }
  }
  ok(before, `site/：${pages.length} ページ`);
}

// --- 5. keys/trusted-public-keys.json ---
// 秘密鍵が公開されている鍵（RFC 8032 のテスト用・開発用）を、本番で信頼しないようにする。
// これらを入れると、誰でも正しい署名を作れてしまう。
const PUBLICLY_KNOWN_KEYS = new Set([
  "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=", // RFC 8032 7.1 TEST 1
  "PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw=", // RFC 8032 7.1 TEST 2
  "/FHNjmIYoaONpH7QAjDwWAgW7RO6MwOsXeuRFUiQgCU=", // RFC 8032 7.1 TEST 3
]);
function checkTrustedKeys() {
  const before = failures;
  const file = "keys/trusted-public-keys.json";
  let keys;
  try {
    keys = JSON.parse(readFileSync(file, "utf8")).keys;
  } catch (e) {
    error(file, `読めません（${e.message}）`);
    return;
  }
  if (!Array.isArray(keys)) {
    error(file, "keys を配列にしてください");
    return;
  }
  for (const [index, entry] of keys.entries()) {
    const id = String(entry?.id ?? "");
    if (PUBLICLY_KNOWN_KEYS.has(entry?.publicKey)) {
      error(file, `${index + 1} 件目（${id}）は、秘密鍵が公開されているテスト用の鍵です。本番では信頼できません`);
    }
    if (id === "dev" || id.startsWith("rfc8032")) {
      error(file, `${index + 1} 件目の id「${id}」は開発用・テスト用の鍵の名前です。本番の鍵を入れてください（docs/signing.md）`);
    }
  }
  if (keys.length === 0) {
    notice(`${file} に鍵がありません。公開する前に、scripts/keygen.sh で作った 2 本の公開鍵を入れてください`);
  }
  ok(before, `${file}：公開されている鍵は入っていません`);
}

// --- 6. シェルのスクリプト ---
// macOS の bash 3.2 は、UTF-8 の設定のとき、全角文字の先頭のバイトを英字として扱う。
// そのため「$host）」のように、変数のすぐ後ろに全角文字があると、変数名の一部と読まれて失敗する
// （set -u なら unbound variable、そうでなければ空になる）。「${host}）」のように波かっこで囲む。
function checkShellVariables() {
  const before = failures;
  const files = [];
  for (const dir of [".github/scripts", "scripts", ".github/workflows"]) {
    if (!existsSync(dir)) continue;
    for (const name of readdirSync(dir)) {
      if (/\.(sh|ya?ml)$/.test(name)) files.push(join(dir, name));
    }
  }
  for (const file of files) {
    readFileSync(file, "utf8").split("\n").forEach((line, index) => {
      const match = /\$([A-Za-z_][A-Za-z0-9_]*)[^\x00-\x7F]/.exec(line);
      if (match) {
        error(file, `${index + 1} 行目：$${match[1]} のすぐ後ろに全角文字があります。\${${match[1]}} と波かっこで囲んでください（macOS の bash が変数名の一部と読むため）`);
      }
    });
  }
  ok(before, `シェルのスクリプト：変数の書き方に問題はありません（${files.length} ファイル）`);
}

// --- 4. deploy/ ---
function checkDeploy() {
  const before = failures;
  const file = "deploy/package.json";
  let pkg;
  let lock;
  try {
    pkg = JSON.parse(readFileSync(file, "utf8"));
    lock = JSON.parse(readFileSync("deploy/package-lock.json", "utf8"));
  } catch (e) {
    error(file, `読めません（${e.message}）`);
    return;
  }
  const wanted = pkg.devDependencies?.wrangler ?? pkg.dependencies?.wrangler;
  if (typeof wanted !== "string" || !/^\d+\.\d+\.\d+$/.test(wanted)) {
    error(file, `wrangler の版は完全に固定してください（例 "4.143.0"。今は ${JSON.stringify(wanted)}）`);
    return;
  }
  const locked = lock.packages?.["node_modules/wrangler"]?.version;
  if (locked !== wanted) {
    error("deploy/package-lock.json", `wrangler の版（${locked}）が package.json（${wanted}）と違います。npm install --package-lock-only で作り直してください`);
    return;
  }
  ok(before, `deploy/：wrangler ${wanted}`);
}

checkWrangler();
checkHeaders();
checkHtml();
checkDeploy();
checkTrustedKeys();
checkShellVariables();

if (failures > 0) {
  console.error(`問題が ${failures} 件あります`);
  process.exit(1);
}
