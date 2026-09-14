import type { MetadataRoute } from "next";
import { toCanonicalUrl } from "@/lib/seo";

const urls = [
  "/",
  "/docs",
  "/docs/getting-started",
  "/docs/loading-videos",
  "/docs/playback",
  "/docs/opacity",
  "/docs/zoom-pan",
  "/docs/filters",
  "/docs/lock-mode",
  "/docs/keyboard-shortcuts",
  "/changelog",
];

export default function sitemap(): MetadataRoute.Sitemap {
  return urls.map((path) => ({
    url: toCanonicalUrl(path),
    changeFrequency: path === "/" ? "weekly" : "monthly",
    priority: path === "/" ? 1 : path === "/docs" ? 0.9 : 0.7,
  }));
}
