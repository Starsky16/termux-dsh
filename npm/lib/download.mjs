import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { readFile } from "node:fs/promises";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

const DEFAULT_REPO = "Starsky16/termux-dsh";
const DEFAULT_BASE = `https://github.com/${DEFAULT_REPO}/releases/download`;

export function releaseTag(version) {
  return `v${version}`;
}

export function releaseUrl(version, asset) {
  const base = (process.env.TDSH_RELEASE_BASE || DEFAULT_BASE).replace(/\/+$/, "");
  return `${base}/${releaseTag(version)}/${asset}`;
}

export async function download(url, dest) {
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`下载失败 ${res.status} ${url}`);
  if (!res.body) throw new Error(`响应无 body：${url}`);
  await pipeline(Readable.fromWeb(res.body), createWriteStream(dest));
  return dest;
}

export async function verifySha256(file, expected) {
  const hash = createHash("sha256");
  hash.update(await readFile(file));
  return hash.digest("hex") === String(expected).trim().toLowerCase();
}

export function parseSha256File(text) {
  const m = String(text).trim().match(/^([0-9a-fA-F]{64})/);
  if (!m) throw new Error("sha256 文件格式不正确");
  return m[1].toLowerCase();
}
