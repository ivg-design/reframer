import type { NextConfig } from "next";

const isProd = process.env.NODE_ENV === "production";
// Only use assetPrefix when deployed behind forge rewrite (not on direct vercel.app access)
const isForgeContext = process.env.NEXT_PUBLIC_SITE_URL?.includes("forge.mograph.life");

const nextConfig: NextConfig = {
  // Disable image optimization
  images: {
    unoptimized: true,
  },

  // No basePath - routes are at root, forge rewrites handle the /apps/reframer prefix
  // Only add assetPrefix when accessed via forge.mograph.life rewrite
  assetPrefix: isProd && isForgeContext ? "/apps/reframer" : "",

  // Environment variables exposed to browser
  env: {
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000",
  },

  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          {
            key: "X-Robots-Tag",
            value: "index, follow, max-snippet:-1, max-image-preview:large, max-video-preview:-1",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
