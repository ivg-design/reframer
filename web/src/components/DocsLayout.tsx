"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import React from "react";
import { asset } from "@/lib/config";
import {
  Rocket,
  FileVideo,
  Play,
  ZoomIn,
  Eye,
  SlidersHorizontal,
  Lock,
  Keyboard,
} from "lucide-react";

// Keyboard key component for styled key caps
export function Kbd({ children, wide }: { children: React.ReactNode; wide?: boolean }) {
  return (
    <kbd className={`inline-flex items-center justify-center h-[28px] px-2 mx-0.5 text-[13px] font-semibold font-mono text-white bg-gradient-to-b from-[#3a3a3a] to-[#2a2a2a] border border-[#4a4a4a] border-b-[#1a1a1a] rounded-md shadow-[0_2px_0_#1a1a1a,inset_0_1px_0_rgba(255,255,255,0.1)] whitespace-nowrap ${wide ? 'min-w-[60px]' : 'min-w-[28px]'}`}>
      {children}
    </kbd>
  );
}

// Mouse scroll wheel component - side view with scroll arrows
export function ScrollWheel() {
  return (
    <span className="inline-flex items-center justify-center gap-0.5 h-[28px] px-2 mx-0.5 bg-gradient-to-b from-[#3a3a3a] to-[#2a2a2a] border border-[#4a4a4a] border-b-[#1a1a1a] rounded-md shadow-[0_2px_0_#1a1a1a,inset_0_1px_0_rgba(255,255,255,0.1)]">
      {/* Up arrow */}
      <svg width="8" height="8" viewBox="0 0 8 8" className="text-[#888]">
        <path d="M4 1L7 5H1L4 1Z" fill="currentColor" />
      </svg>
      {/* Wheel icon - side view */}
      <span className="w-[10px] h-[14px] rounded-[3px] bg-gradient-to-r from-[#555] via-[#666] to-[#555] border border-[#444] flex items-center justify-center">
        <span className="w-[6px] h-[2px] bg-[#888] rounded-full" />
      </span>
      {/* Down arrow */}
      <svg width="8" height="8" viewBox="0 0 8 8" className="text-[#888]">
        <path d="M4 7L1 3H7L4 7Z" fill="currentColor" />
      </svg>
    </span>
  );
}

// Helper to parse shortcut strings and render as Kbd components
export function KeyCombo({ keys }: { keys: string }) {
  // Special multi-word keys that should stay together
  const multiWordKeys: Record<string, boolean> = {
    'Page Up': true,
    'Page Down': true,
  };

  // Check for multi-word keys first
  let remaining = keys;
  const parts: string[] = [];

  for (const multiKey of Object.keys(multiWordKeys)) {
    if (remaining.includes(multiKey)) {
      const idx = remaining.indexOf(multiKey);
      if (idx > 0) {
        parts.push(...remaining.substring(0, idx).trim().split(/\s+/).filter(Boolean));
      }
      parts.push(multiKey);
      remaining = remaining.substring(idx + multiKey.length).trim();
    }
  }

  // Add any remaining parts
  if (remaining) {
    parts.push(...remaining.split(/\s+/).filter(Boolean));
  }

  return (
    <span className="inline-flex items-center gap-1 flex-wrap">
      {parts.map((part, i) => {
        // Handle "or" text between alternatives
        if (part.toLowerCase() === 'or') {
          return <span key={i} className="text-[var(--text-disabled)] text-xs mx-1">or</span>;
        }
        // Wide keys for Page Up/Down, Space, Enter, etc.
        const isWide = ['Page Up', 'Page Down', 'Space', 'Enter', 'Esc'].includes(part);
        // Render each key
        return <Kbd key={i} wide={isWide}>{part}</Kbd>;
      })}
    </span>
  );
}

const navigation = [
  {
    title: "GETTING STARTED",
    items: [
      { href: "/docs/getting-started", label: "Getting Started", icon: Rocket },
      { href: "/docs/loading-videos", label: "Loading Videos", icon: FileVideo },
    ],
  },
  {
    title: "CORE FEATURES",
    items: [
      { href: "/docs/playback", label: "Playback Controls", icon: Play },
      { href: "/docs/zoom-pan", label: "Zoom & Pan", icon: ZoomIn },
      { href: "/docs/opacity", label: "Opacity", icon: Eye },
      { href: "/docs/filters", label: "Filters", icon: SlidersHorizontal },
      { href: "/docs/lock-mode", label: "Lock Mode", icon: Lock },
    ],
  },
  {
    title: "REFERENCE",
    items: [
      { href: "/docs/keyboard-shortcuts", label: "Keyboard Shortcuts", icon: Keyboard },
    ],
  },
];

export function DocsLayout({
  children,
  title,
  description,
  breadcrumb,
}: {
  children: React.ReactNode;
  title: string;
  description: string;
  breadcrumb: string;
}) {
  const pathname = usePathname();

  return (
    <div className="flex min-h-screen min-w-0 bg-[var(--bg-page)]">
      {/* Sidebar */}
      <aside className="hidden w-[280px] h-screen sticky top-0 shrink-0 flex-col gap-8 p-6 pt-8 bg-[var(--bg-surface)] border-r border-[var(--border-subtle)] lg:flex">
        <Link href={asset("/")} className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg overflow-hidden">
            <Image src={asset("/media/reframer/icon-64.webp")} alt="Reframer" width={32} height={32} className="w-full h-full object-cover" />
          </div>
          <span className="text-lg font-bold text-white">Reframer</span>
        </Link>

        <nav className="flex flex-col gap-2">
          {navigation.map((section, sectionIndex) => (
            <div key={sectionIndex} className="flex flex-col gap-1">
              <span className="px-3 py-2 text-[11px] font-semibold text-[var(--text-disabled)] tracking-[1px]">
                {section.title}
              </span>
              {section.items.map((item) => {
                const isActive = pathname === item.href || pathname === asset(item.href);
                return (
                  <Link
                    key={item.href}
                    href={asset(item.href)}
                    className={`flex items-center gap-2.5 px-3 py-2.5 rounded-lg transition-colors ${
                      isActive
                        ? "bg-[var(--accent-tint)] text-[var(--accent-primary)]"
                        : "text-[var(--text-tertiary)] hover:text-white hover:bg-[var(--bg-elevated)]"
                    }`}
                  >
                    <item.icon className="w-4 h-4" />
                    <span className="text-sm font-medium">{item.label}</span>
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>
      </aside>

      {/* Content */}
      <main className="flex min-w-0 flex-1 flex-col gap-8 overflow-y-auto px-4 py-8 sm:px-6 md:p-10 lg:gap-10 lg:p-12 lg:px-16">
        {/* Breadcrumb */}
        <div className="flex items-center gap-2">
          <Link href={asset("/docs")} className="text-[13px] text-[var(--text-tertiary)] hover:text-white">
            Docs
          </Link>
          <span className="text-[13px] text-[var(--text-disabled)]">/</span>
          <span className="text-[13px] font-medium text-white">{breadcrumb}</span>
        </div>

        {/* Header */}
        <div className="flex flex-col gap-3">
          <h1 className="text-3xl font-bold text-white tracking-[-1px] sm:text-[40px]">{title}</h1>
          <p className="text-base text-[var(--text-tertiary)] sm:text-lg">{description}</p>
        </div>

        <div className="w-full h-px bg-[var(--border-subtle)]" />

        {/* Page Content */}
        <div className="flex flex-col gap-10 max-w-[800px]">{children}</div>
      </main>
    </div>
  );
}

export function DocsSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-4">
      <h2 className="text-2xl font-semibold text-white">{title}</h2>
      {children}
    </section>
  );
}

export function DocsParagraph({ children }: { children: React.ReactNode }) {
  return <p className="text-base text-[var(--text-secondary)] leading-[1.7]">{children}</p>;
}

export function DocsTable({ headers, rows }: { headers: string[]; rows: React.ReactNode[][] }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-[var(--border-subtle)]">
      <div className="min-w-[620px]">
      <div className="flex bg-[var(--bg-elevated)] px-5 py-3">
        {headers.map((header, index) => (
          <span
            key={index}
            className={`text-sm font-semibold text-[var(--text-secondary)] ${index === 0 ? "w-[240px]" : "flex-1"}`}
          >
            {header}
          </span>
        ))}
      </div>
      {rows.map((row, rowIndex) => (
        <div
          key={rowIndex}
          className={`flex items-center px-5 py-3.5 ${rowIndex < rows.length - 1 ? "border-b border-[var(--border-subtle)]" : ""}`}
        >
          {row.map((cell, cellIndex) => (
            <span
              key={cellIndex}
              className={`text-sm ${cellIndex === 0 ? "w-[240px] text-[var(--text-secondary)]" : "flex-1 text-[var(--text-tertiary)]"}`}
            >
              {cell}
            </span>
          ))}
        </div>
      ))}
      </div>
    </div>
  );
}

export function DocsNextSteps({ links }: { links: { href: string; title: string; description: string }[] }) {
  return (
    <section className="flex flex-col gap-5">
      <h2 className="text-2xl font-semibold text-white">Next Steps</h2>
      <div className="flex flex-col gap-4 sm:flex-row">
        {links.map((link, index) => (
          <Link
            key={index}
            href={asset(link.href)}
            className="flex-1 flex flex-col gap-3 p-5 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] hover:border-[var(--border-default)] transition-colors"
          >
            <span className="text-base font-semibold text-white">{link.title}</span>
            <span className="text-sm text-[var(--text-tertiary)]">{link.description}</span>
            <span className="text-sm font-medium text-[var(--accent-primary)]">Read more →</span>
          </Link>
        ))}
      </div>
    </section>
  );
}
