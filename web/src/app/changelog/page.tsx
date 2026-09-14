import Image from "next/image";
import Link from "next/link";
import { asset } from "@/lib/config";
import { createPageMetadata } from "@/lib/seo";

export const metadata = createPageMetadata({
  title: "Reframer Changelog | Release Notes",
  description:
    "Track Reframer releases, improvements, and fixes for the transparent video overlay app on macOS.",
  path: "/changelog",
});

export default function ChangelogPage() {
  return (
    <div className="flex flex-col min-h-full bg-[var(--bg-page)]">
      <Header />
      <main>
        <Hero />
        <Content />
      </main>
    </div>
  );
}

function Header() {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border-subtle)] bg-[var(--bg-surface)] px-4 py-3 sm:px-6 lg:min-h-[72px] lg:flex-nowrap lg:px-20 lg:py-0">
      <Link href={asset("/")} className="flex items-center gap-3">
        <div className="w-8 h-8 rounded-lg overflow-hidden">
          <Image src={asset("/media/reframer/icon-64.webp")} alt="Reframer" width={32} height={32} className="w-full h-full object-cover" />
        </div>
        <span className="text-lg font-bold text-white tracking-[1px]">Reframer</span>
      </Link>

      <nav className="order-3 flex w-full items-center justify-center gap-5 border-t border-[var(--border-subtle)] pt-3 sm:gap-8 lg:order-none lg:w-auto lg:border-0 lg:pt-0">
        <Link href={asset("/")} className="text-sm text-[var(--text-tertiary)] hover:text-white transition-colors">
          Home
        </Link>
        <Link href={asset("/docs")} className="text-sm text-[var(--text-tertiary)] hover:text-white transition-colors">
          Documentation
        </Link>
        <Link href={asset("/changelog")} className="text-sm font-medium text-[var(--accent-primary)]">
          Changelog
        </Link>
      </nav>

      <a
        href="https://contra.com/products/UBCf87LD-reframer"
        data-forge-action="product_listing"
        target="_blank"
        rel="noopener noreferrer"
        className="px-5 py-2.5 rounded-lg bg-[var(--accent-primary)] text-white text-sm font-semibold hover:opacity-90 transition-opacity"
      >
        Download Beta
      </a>
    </header>
  );
}

function Hero() {
  return (
    <section className="flex flex-col items-center gap-4 px-4 py-14 sm:px-6 md:py-20 lg:px-20">
      <h1 className="text-4xl font-bold text-white tracking-[-1px] sm:text-[56px]">Changelog</h1>
      <p className="text-lg text-[var(--text-tertiary)] text-center">
        Track the latest updates, improvements, and bug fixes in Reframer.
      </p>
    </section>
  );
}

function Content() {
  const releases = [
    {
      version: "v0.8.1-beta.3",
      date: "February 2, 2026",
      isLatest: true,
      added: [
        "Video filters system with 11 real-time effects",
        "Filter panel for advanced multi-filter combinations with chainable effects",
        "Click-to-cycle filter selection with hold-for-menu UI",
        "Separate Brightness, Contrast, and Exposure controls",
        "Edge detection filter for tracing workflows",
        "Line Art filter for clean line drawings",
        "Sharpen and Unsharp Mask for detail enhancement",
        "Monochrome filter with customizable tint color",
        "Invert and Noir quick filters",
        "Global frame step shortcuts (⌘ Page Up/Down)",
        "Smooth timeline scrubbing",
        "macOS 26 Tahoe Liquid Glass visual effect",
      ],
      changed: [
        "Arrow keys now pan video (1px, 10px with ⇧, 100px with ⇧⌘)",
        "Scroll wheel steps frames, ⇧+Scroll zooms",
        "Simplified Help menu to single Documentation item",
        "Toolbar positioned below video canvas",
        "Video canvas with rounded corners",
        "Pan works at any zoom level",
      ],
      fixed: [
        "Help menu actions conflicting with system selectors",
        "Smooth scrubbing and global frame step shortcuts",
        "Scrubbar not resetting when loading a new video",
        "Toolbar/canvas alignment issues",
        "Filter panel layout and toggle alignment",
        "Dropdown menu filter selection",
      ],
    },
    {
      version: "v0.8.0-beta.1",
      date: "January 31, 2026",
      isLatest: false,
      added: [
        "Video filters feature with click-to-cycle and hold-for-menu UI",
        "Filter chaining support with multi-select toggle menu",
        "Filter panel showing only active filter parameters",
        "Separate Brightness/Contrast filters with improved panel UI",
        "Line Art filter (renamed from Line Overlay)",
        "Edge glow indicators for resize handle discovery",
      ],
      changed: [
        "Filter parameter controls simplified",
        "Quick filter menu items disambiguated for accessibility",
      ],
      fixed: [
        "Filter selection issues and exposure control",
        "Long-press filter open behavior",
        "Panel layout with top-aligned filters",
      ],
    },
    {
      version: "v0.7.0",
      date: "January 31, 2026",
      isLatest: false,
      added: [
        "Pure AppKit implementation (migrated from SwiftUI)",
        "Transparent frameless window with video overlay",
        "Always-on-top window mode",
        "Frame-accurate video navigation",
        "Zoom (10-1000%) and pan controls",
        "Adjustable opacity (2-100%)",
        "Lock mode to click through video",
        "Global shortcuts that work from any app",
        "Apple Help Book documentation",
        "DocC developer documentation",
        "CI workflow for automated builds",
      ],
      changed: [
        "Complete architecture rewrite for better performance",
        "Window dragging from center, resize from edges",
      ],
      fixed: [
        "All SwiftUI-related deprecation warnings",
        "Window and canvas layout issues",
        "Accessibility prompt handling",
      ],
    },
    {
      version: "v0.1.0",
      date: "January 30, 2026",
      isLatest: false,
      added: [
        "Initial project setup",
        "Basic video playback with AVFoundation",
        "Drag and drop video loading",
        "Play/pause functionality",
      ],
    },
  ];

  return (
    <section className="flex flex-col items-center gap-12 px-4 py-8 pb-16 sm:px-6 md:py-10 md:pb-20 lg:px-20">
      <div className="flex w-full max-w-[900px] flex-col gap-12">
        {releases.map((release, index) => (
          <div key={index} className="flex flex-col gap-6">
            {/* Version Header */}
            <div className="flex flex-wrap items-center gap-3 sm:gap-4">
              {release.isLatest && (
                <span className="px-3 py-1.5 rounded-full bg-gradient-to-br from-[var(--accent-primary)] to-[var(--accent-light)] text-[11px] font-semibold text-white">
                  Latest
                </span>
              )}
              <span className="text-2xl font-semibold text-white font-mono">{release.version}</span>
              <span className="text-sm text-[var(--text-disabled)]">{release.date}</span>
            </div>

            {/* Version Body */}
            <div className="flex flex-col gap-5 border-l-2 border-[var(--border-subtle)] pl-4 sm:pl-6">
              {release.added && release.added.length > 0 && (
                <ChangeSection type="added" items={release.added} />
              )}
              {release.changed && release.changed.length > 0 && (
                <ChangeSection type="changed" items={release.changed} />
              )}
              {release.fixed && release.fixed.length > 0 && (
                <ChangeSection type="fixed" items={release.fixed} />
              )}
            </div>
          </div>
        ))}
      </div>

      {/* GitHub Link */}
      <div className="flex flex-col items-center gap-4 pt-8">
        <p className="text-sm text-[var(--text-tertiary)]">
          View the full commit history on GitHub
        </p>
        <a
          href="https://github.com/ivg-design/reframer"
          data-forge-action="repository"
          target="_blank"
          rel="noopener noreferrer"
          className="max-w-full break-all rounded-lg border border-[var(--border-default)] px-4 py-2.5 text-sm font-medium text-[var(--text-secondary)] transition-colors hover:border-[var(--text-tertiary)] sm:px-5"
        >
          github.com/ivg-design/reframer
        </a>
      </div>
    </section>
  );
}

function ChangeSection({ type, items }: { type: "added" | "changed" | "fixed"; items: string[] }) {
  const config = {
    added: { label: "Added", bg: "bg-[#22C55E18]", text: "text-[#22C55E]" },
    changed: { label: "Changed", bg: "bg-[#3B82F618]", text: "text-[#3B82F6]" },
    fixed: { label: "Fixed", bg: "bg-[#EF444418]", text: "text-[#EF4444]" },
  };

  const { label, bg, text } = config[type];

  return (
    <div className="flex flex-col gap-3">
      <span className={`w-fit px-2.5 py-1 rounded-md ${bg} text-xs font-semibold ${text}`}>
        {label}
      </span>
      <div className="flex flex-col gap-2">
        {items.map((item, index) => (
          <div key={index} className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-[15px] text-[var(--text-secondary)] leading-[1.6]">{item}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
