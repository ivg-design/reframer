import type { Metadata } from "next";
import localFont from "next/font/local";
import WebVitalsReporter from "@/components/WebVitalsReporter";
import { CANONICAL_HOST, createPageMetadata } from "@/lib/seo";
import "./globals.css";

const siteName = "Reframer - Transparent Video Overlay for macOS";
const description =
  "A transparent video overlay for macOS. Keep reference visible while you work for animation, motion design, and tutorial breakdown workflows.";

const inter = localFont({
  src: "./fonts/inter-latin.woff2",
  display: "swap",
  variable: "--font-inter",
  weight: "400 700",
});

const dmMono = localFont({
  src: [
    { path: "./fonts/dm-mono-400-latin.woff2", weight: "400" },
    { path: "./fonts/dm-mono-500-latin.woff2", weight: "500" },
  ],
  display: "swap",
  variable: "--font-dm-mono",
});

export const metadata: Metadata = {
  metadataBase: new URL(CANONICAL_HOST),
  ...createPageMetadata({ title: siteName, description, path: "/" }),
  keywords: [
    "Reframer",
    "transparent video overlay",
    "macOS overlay",
    "animation reference tool",
    "video reference app",
  ],
  authors: [{ name: "IVG Design" }],
  creator: "IVG Design",
  publisher: "IVG Design",
  robots: {
    index: true,
    follow: true,
    "max-snippet": -1,
    "max-image-preview": "large",
    "max-video-preview": -1,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`h-full ${inter.variable} ${dmMono.variable}`}>
      <head>
        <script src="/shared/js/growth-events.js" defer />
      </head>
      <body className="h-full font-primary bg-[var(--bg-page)] text-[var(--text-primary)] antialiased">
        {children}
        <WebVitalsReporter />
      </body>
    </html>
  );
}
