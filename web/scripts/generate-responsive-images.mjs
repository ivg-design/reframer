import { createHash } from "node:crypto";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const root = process.cwd();
const outputDirectory = path.join(root, "public/media/reframer");

const sources = [
  {
    name: "demo-poster",
    path: "assets/media-source/demo-poster.png",
    sha256: "5d26905ebac10f6f687e272d9d0a4f822bfb00278a4b1455691aac1eb25e3346",
    widths: [1200],
  },
  {
    name: "main-screen",
    path: "assets/media-source/main-screen.png",
    sha256: "6580c034ad5ef42d9458c24df4df6494df2c78314f20d27dc461679a3ee64982",
    widths: [480, 768, 1200],
  },
  {
    name: "shortcuts",
    path: "assets/media-source/shortcuts.png",
    sha256: "a5d15e03495f5a661ee3782b816ee54e02590d46946d603c3b1034fd00234344",
    widths: [256, 512],
  },
  {
    name: "filters",
    path: "assets/media-source/filters.png",
    sha256: "ff717db870a34a1fdb93f8ae2e0eb0a0f2089b658f1feaa82daa4c703849a87f",
    widths: [384, 768],
  },
  {
    name: "icon",
    path: "public/icon.png",
    sha256: "473eafedcbefa46d264e7154d6175199987276b59db82f8148e479705f396c35",
    widths: [64, 128],
  },
];

await mkdir(outputDirectory, { recursive: true });
const manifest = [];

for (const source of sources) {
  const sourcePath = path.join(root, source.path);
  const sourceBuffer = await readFile(sourcePath);
  const digest = createHash("sha256").update(sourceBuffer).digest("hex");

  if (digest !== source.sha256) {
    throw new Error(`Source hash mismatch for ${source.path}: ${digest}`);
  }

  const sourceMetadata = await sharp(sourceBuffer).metadata();
  const sourceStats = await stat(sourcePath);
  const outputs = [];

  for (const width of source.widths) {
    const filename = `${source.name}-${width}.webp`;
    const outputPath = path.join(outputDirectory, filename);

    await sharp(sourceBuffer)
      .resize({ width, withoutEnlargement: true })
      .webp({ quality: 82, effort: 6, smartSubsample: true })
      .toFile(outputPath);

    const outputMetadata = await sharp(outputPath).metadata();
    const outputStats = await stat(outputPath);
    outputs.push({
      file: `public/media/reframer/${filename}`,
      width: outputMetadata.width,
      height: outputMetadata.height,
      bytes: outputStats.size,
    });
  }

  manifest.push({
    source: source.path,
    sha256: digest,
    width: sourceMetadata.width,
    height: sourceMetadata.height,
    bytes: sourceStats.size,
    outputs,
  });
}

await writeFile(
  path.join(root, "assets/responsive-images.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
);

for (const source of manifest) {
  console.log(`${source.source} (${source.bytes} bytes)`);
  for (const output of source.outputs) {
    console.log(`  -> ${output.file} ${output.width}x${output.height} (${output.bytes} bytes)`);
  }
}
