import Image from "next/image";
import Link from "next/link";
import { asset } from "@/lib/config";
import { createPageMetadata } from "@/lib/seo";
import {
  Search,
  Rocket,
  ArrowRight,
  Play,
  Eye,
  ZoomIn,
  Lock,
  SlidersHorizontal,
  Keyboard,
  FileVideo,
} from "lucide-react";

export const metadata = createPageMetadata({
  title: "Reframer Documentation | Guides and Reference",
  description:
    "Official Reframer documentation for installation, playback, opacity, zoom, filters, lock mode, and keyboard shortcuts.",
  path: "/docs",
});

export default function DocsIndexPage() {
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
        <div className="w-9 h-9 rounded-[10px] overflow-hidden">
          <Image src={asset("/media/reframer/icon-64.webp")} alt="Reframer" width={36} height={36} className="w-full h-full object-cover" />
        </div>
        <span className="text-xl font-bold text-white tracking-[-0.5px]">Reframer</span>
        <span className="hidden text-xl text-[var(--text-disabled)] sm:inline">/</span>
        <span className="hidden text-xl font-medium text-[var(--text-secondary)] sm:inline">Docs</span>
      </Link>

      <nav className="order-3 flex w-full items-center justify-center gap-8 border-t border-[var(--border-subtle)] pt-3 lg:order-none lg:w-auto lg:border-0 lg:pt-0">
        <Link href={asset("/")} className="text-sm text-[var(--text-tertiary)] hover:text-white transition-colors">
          Home
        </Link>
        <Link href={asset("/changelog")} className="text-sm text-[var(--text-tertiary)] hover:text-white transition-colors">
          Changelog
        </Link>
      </nav>

      <Link
        href="https://contra.com/products/UBCf87LD-reframer"
        data-forge-action="product_listing"
        target="_blank"
        rel="noopener noreferrer"
        className="px-5 py-2.5 rounded-lg bg-[var(--accent-primary)] text-white text-sm font-semibold hover:opacity-90 transition-opacity"
      >
        Download Beta
      </Link>
    </header>
  );
}

function Hero() {
  return (
    <section className="flex flex-col items-center gap-6 px-4 py-14 sm:px-6 md:py-20 lg:px-20">
      <h1 className="text-4xl font-bold text-white tracking-[-2px] sm:text-[56px]">Documentation</h1>
      <p className="text-lg text-[var(--text-tertiary)] text-center sm:text-xl">
        Learn how to use Reframer effectively in your creative workflow.
      </p>

      {/* Search Box */}
      <div className="flex w-full max-w-[500px] items-center gap-3 rounded-xl border border-[var(--border-default)] bg-[var(--bg-surface)] px-4 py-3.5 sm:px-5">
        <Search className="w-5 h-5 text-[var(--text-disabled)]" />
        <span className="text-[15px] text-[var(--text-disabled)]">Search documentation...</span>
        <div className="ml-auto hidden rounded-md border border-[var(--border-default)] bg-[var(--bg-elevated)] px-2 py-1 sm:block">
          <span className="text-xs font-medium text-[var(--text-disabled)]">⌘K</span>
        </div>
      </div>
    </section>
  );
}

function Content() {
  return (
    <section className="flex flex-col gap-10 px-4 py-8 pb-16 sm:px-6 md:gap-12 md:py-10 md:pb-20 lg:px-20">
      {/* Getting Started */}
      <div className="flex flex-col gap-6">
        <span className="text-xs font-semibold text-[var(--accent-primary)] tracking-[1px]">
          GETTING STARTED
        </span>
        <Link
          href={asset("/docs/getting-started")}
          className="flex flex-col items-start gap-5 rounded-2xl border border-[var(--border-subtle)] bg-[var(--bg-surface)] p-6 transition-colors hover:border-[var(--border-default)] sm:flex-row sm:items-center sm:gap-6 sm:p-8"
        >
          <div className="flex items-center justify-center w-16 h-16 rounded-2xl bg-[var(--accent-tint)]">
            <Rocket className="w-8 h-8 text-[var(--accent-primary)]" />
          </div>
          <div className="flex flex-col gap-2 flex-1">
            <h3 className="text-xl font-semibold text-white">Getting Started</h3>
            <p className="text-[var(--text-tertiary)]">
              Install Reframer, load your first video, and learn the basic controls. Get up and running in minutes.
            </p>
          </div>
          <div className="flex items-center gap-2 text-[var(--accent-primary)]">
            <span className="text-sm font-medium">Read guide</span>
            <ArrowRight className="w-4 h-4" />
          </div>
        </Link>
      </div>

      {/* Core Features */}
      <div className="flex flex-col gap-6">
        <span className="text-xs font-semibold text-[var(--accent-primary)] tracking-[1px]">
          CORE FEATURES
        </span>
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <DocCard
            href="/docs/playback"
            icon={Play}
            title="Playback Controls"
            description="Frame-accurate navigation, timeline scrubbing, and global shortcuts."
          />
          <DocCard
            href="/docs/opacity"
            icon={Eye}
            title="Opacity"
            description="Blend the overlay from 2% to 100% for perfect reference visibility."
          />
          <DocCard
            href="/docs/zoom-pan"
            icon={ZoomIn}
            title="Zoom & Pan"
            description="Inspect details at 10%-1000% zoom with precise pan controls."
          />
          <DocCard
            href="/docs/lock-mode"
            icon={Lock}
            title="Lock Mode"
            description="Click through the video to interact with apps below."
          />
        </div>
      </div>

      {/* Reference */}
      <div className="flex flex-col gap-6">
        <span className="text-xs font-semibold text-[var(--accent-primary)] tracking-[1px]">
          REFERENCE
        </span>
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <DocCard
            href="/docs/filters"
            icon={SlidersHorizontal}
            title="Filters"
            description="11 real-time effects: edges, line art, noir, and more."
            small
          />
          <DocCard
            href="/docs/keyboard-shortcuts"
            icon={Keyboard}
            title="Keyboard Shortcuts"
            description="Complete reference for all keyboard and mouse controls."
            small
          />
          <DocCard
            href="/docs/loading-videos"
            icon={FileVideo}
            title="Loading Videos"
            description="Supported formats, codecs, and troubleshooting tips."
            small
          />
        </div>
      </div>
    </section>
  );
}

function DocCard({
  href,
  icon: Icon,
  title,
  description,
  small = false,
}: {
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  description: string;
  small?: boolean;
}) {
  return (
    <Link
      href={asset(href)}
      className={`flex flex-col gap-4 ${small ? "p-6" : "p-6"} rounded-xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] hover:border-[var(--border-default)] transition-colors`}
    >
      <div
        className={`flex items-center justify-center ${small ? "w-10 h-10 rounded-lg" : "w-12 h-12 rounded-xl"} bg-[var(--accent-tint)]`}
      >
        <Icon className={`${small ? "w-5 h-5" : "w-6 h-6"} text-[var(--accent-primary)]`} />
      </div>
      <div className="flex flex-col gap-1">
        <h3 className={`${small ? "text-base" : "text-lg"} font-semibold text-white`}>{title}</h3>
        <p className={`${small ? "text-sm" : "text-[15px]"} text-[var(--text-tertiary)] leading-[1.5]`}>
          {description}
        </p>
      </div>
      <span className="text-sm font-medium text-[var(--accent-primary)]">Learn more →</span>
    </Link>
  );
}
