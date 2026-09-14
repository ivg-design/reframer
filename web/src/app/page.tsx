"use client";

import { useEffect, useRef, useState } from "react";
import {
  Download,
  Github,
  Sparkles,
  Apple,
  Gift,
  Layers,
  Frame,
  MousePointerClick,
  PenTool,
  LayoutGrid,
  GraduationCap,
  SlidersHorizontal,
  ZoomIn,
  Eye,
  Keyboard,
  Move,
  Film,
  BookOpen,
  X,
} from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { asset, media } from "@/lib/config";
import { softwareApplicationJsonLd } from "@/lib/seo";
import AnswerSection from "@/components/AnswerSection";

export default function LandingPage() {
  return (
    <div className="flex flex-col w-full min-h-full">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApplicationJsonLd) }}
      />
      <link
        rel="preload"
        as="image"
        href={asset("/media/reframer/demo-poster-1200.webp")}
        fetchPriority="high"
      />
      <Header />
      <main>
        <HeroSection />
        <AnswerSection />
        <FeaturesSection />
        <UseCasesSection />
        <MoreFeaturesSection />
        <CTASection />
      </main>
      <Footer />
    </div>
  );
}

function Header() {
  return (
    <header className="flex flex-wrap items-center justify-between min-h-[72px] gap-3 px-4 py-3 sm:px-6 lg:flex-nowrap lg:px-20 lg:py-0 bg-[var(--bg-page)]">
      <Link href={asset("/")} className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-xl overflow-hidden">
          <Image
            src={asset("/media/reframer/icon-64.webp")}
            alt=""
            width={48}
            height={48}
            className="w-full h-full object-cover"
          />
        </div>
        <span className="text-[22px] font-bold text-white tracking-[-0.5px]">
          Reframer
        </span>
      </Link>

      <nav className="order-3 flex w-full items-center justify-center gap-5 border-t border-[var(--border-subtle)] pt-3 sm:gap-8 lg:order-none lg:w-auto lg:border-0 lg:pt-0 lg:gap-10">
        <a
          href="#features"
          className="text-sm font-medium text-[var(--text-secondary)] hover:text-white transition-colors"
        >
          Features
        </a>
        <Link
          href={asset("/docs")}
          className="text-sm font-medium text-[var(--text-secondary)] hover:text-white transition-colors"
        >
          Documentation
        </Link>
        <Link
          href={asset("/changelog")}
          className="text-sm font-medium text-[var(--text-secondary)] hover:text-white transition-colors"
        >
          Changelog
        </Link>
      </nav>

      <div className="flex items-center gap-4">
        <div className="hidden px-3 py-1.5 rounded-full bg-[var(--accent-tint)] sm:block">
          <span className="text-[11px] font-semibold text-[var(--accent-primary)] tracking-[1px]">
            BETA
          </span>
        </div>
        <a href="https://contra.com/products/UBCf87LD-reframer" target="_blank" rel="noopener noreferrer" data-forge-action="product_listing" className="px-5 py-2.5 rounded-lg bg-[var(--accent-primary)] text-[#171719] text-sm font-semibold hover:opacity-90 transition-opacity">
          Download Beta
        </a>
      </div>
    </header>
  );
}

function HeroSection() {
  const [lightbox, setLightbox] = useState<{ type: "image" | "video"; src: string; alt?: string } | null>(null);
  const lightboxRef = useRef<HTMLDivElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (lightbox) closeButtonRef.current?.focus();
  }, [lightbox]);

  function openLightbox(
    event: React.MouseEvent<HTMLButtonElement>,
    item: { type: "image" | "video"; src: string; alt?: string },
  ) {
    triggerRef.current = event.currentTarget;
    setLightbox(item);
  }

  function closeLightbox() {
    setLightbox(null);
    requestAnimationFrame(() => triggerRef.current?.focus());
  }

  function handleDialogKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeLightbox();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = lightboxRef.current?.querySelectorAll<HTMLElement>(
      'button, [href], [tabindex]:not([tabindex="-1"])',
    );
    if (!focusable?.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <>
      <section className="flex flex-col items-center gap-8 px-4 py-16 sm:px-6 md:gap-12 md:py-[100px] lg:px-20 lg:pb-20 bg-[var(--bg-page)]">
        <div className="flex w-full max-w-[900px] flex-col items-center gap-6 md:gap-8">
          <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-[var(--bg-elevated)] border border-[var(--border-default)]">
            <Sparkles className="w-3.5 h-3.5 text-[var(--accent-primary)]" />
            <span className="text-[13px] font-medium text-[var(--text-secondary)]">
              Now in Public Beta
            </span>
          </div>

          <h1 className="w-full max-w-[1000px] text-[44px] font-bold leading-none tracking-[-2px] text-white text-center sm:text-[58px] md:text-[80px] md:tracking-[-4px]">
            Reframe your workflow.
          </h1>

          <p className="w-full max-w-[750px] text-lg font-normal leading-[1.5] text-[var(--text-tertiary)] text-center md:text-[22px]">
            A transparent video overlay for macOS. Keep reference visible while
            you work — perfect for animation, motion design, and learning from
            tutorials.
          </p>

          <div className="flex w-full flex-col items-stretch gap-3 sm:w-auto sm:flex-row sm:items-center sm:gap-4">
            <a href="https://contra.com/products/UBCf87LD-reframer" target="_blank" rel="noopener noreferrer" data-forge-action="product_listing" className="flex items-center gap-2.5 px-7 py-3.5 rounded-[10px] bg-gradient-to-br from-[var(--accent-primary)] to-[var(--accent-light)] text-[#171719] font-semibold hover:opacity-90 transition-opacity">
              <Download className="w-[18px] h-[18px]" />
              <span>Download for macOS</span>
            </a>
            <a href="https://github.com/ivg-design/reframer" target="_blank" rel="noopener noreferrer" data-forge-action="repository" className="flex items-center gap-2.5 px-7 py-3.5 rounded-[10px] border border-[var(--border-default)] text-[var(--text-secondary)] font-medium hover:border-[var(--text-tertiary)] transition-colors">
              <Github className="w-[18px] h-[18px]" />
              <span>View on GitHub</span>
            </a>
          </div>
        </div>

        {/* Demo Video */}
        <button
          type="button"
          aria-label="Open enlarged Reframer demonstration video"
          onClick={(event) => openLightbox(event, { type: "video", src: media("/assets/reframer-demo.mp4") })}
          className="w-full max-w-[1000px] rounded-2xl overflow-hidden border border-[var(--border-subtle)] shadow-2xl cursor-pointer transition-transform duration-300 hover:scale-[1.02]"
        >
          <video
            autoPlay
            loop
            muted
            playsInline
            poster={asset("/media/reframer/demo-poster-1200.webp")}
            aria-label="Silent demonstration of Reframer playing reference footage in a transparent overlay"
            className="w-full h-auto"
          >
            <source src={media("/assets/reframer-demo.mp4")} type="video/mp4" />
          </video>
        </button>

        {/* Screenshots showcase - aspect ratio preserved at h-[420px] */}
        <div className="flex h-auto w-full max-w-[1240px] flex-col items-center justify-center gap-5 min-[1400px]:h-[420px] min-[1400px]:flex-row">
          {/* Shortcuts - left (973x1908 → ~214px wide at 420px height) */}
          <button
            type="button"
            aria-label="Open full-size Reframer keyboard shortcuts panel"
            onClick={(event) => openLightbox(event, { type: "image", src: media("/assets/shortcuts.png"), alt: "Reframer keyboard shortcuts panel" })}
            className="w-full max-w-[256px] rounded-xl overflow-hidden border border-[var(--border-subtle)] shadow-lg cursor-pointer transition-transform duration-300 hover:scale-[1.03] min-[1400px]:h-full min-[1400px]:w-auto min-[1400px]:max-w-none"
            style={{ aspectRatio: "973 / 1908" }}
          >
            <picture className="block h-full">
              <source
                srcSet={`${asset("/media/reframer/shortcuts-256.webp")} 256w, ${asset("/media/reframer/shortcuts-512.webp")} 512w`}
                sizes="(max-width: 768px) 55vw, 214px"
                type="image/webp"
              />
              <img
                src={asset("/media/reframer/shortcuts-256.webp")}
                alt="Reframer keyboard shortcuts panel"
                width={973}
                height={1908}
                loading="lazy"
                decoding="async"
                className="w-full h-full object-contain"
              />
            </picture>
          </button>

          {/* Main screen - center (3648x2350 → ~652px wide at 420px height) */}
          <button
            type="button"
            aria-label="Open full-size Reframer transparent video window"
            onClick={(event) => openLightbox(event, { type: "image", src: media("/assets/main-screen.png"), alt: "Reframer transparent video window and playback controls" })}
            className="w-full rounded-xl overflow-hidden border border-[var(--border-subtle)] shadow-lg cursor-pointer transition-transform duration-300 hover:scale-[1.03] min-[1400px]:h-full min-[1400px]:w-auto"
            style={{ aspectRatio: "3648 / 2350" }}
          >
            <picture className="block h-full">
              <source
                srcSet={`${asset("/media/reframer/main-screen-480.webp")} 480w, ${asset("/media/reframer/main-screen-768.webp")} 768w, ${asset("/media/reframer/main-screen-1200.webp")} 1200w`}
                sizes="(max-width: 768px) 100vw, 652px"
                type="image/webp"
              />
              <img
                src={asset("/media/reframer/main-screen-768.webp")}
                alt="Reframer transparent video window and playback controls"
                width={3648}
                height={2350}
                loading="lazy"
                decoding="async"
                className="w-full h-full object-contain"
              />
            </picture>
          </button>

          {/* Filters - right (1052x1340 → ~330px wide at 420px height) */}
          <button
            type="button"
            aria-label="Open full-size Reframer video filters panel"
            onClick={(event) => openLightbox(event, { type: "image", src: media("/assets/filters.png"), alt: "Reframer video filters panel" })}
            className="w-full max-w-[384px] rounded-xl overflow-hidden border border-[var(--border-subtle)] shadow-lg cursor-pointer transition-transform duration-300 hover:scale-[1.03] min-[1400px]:h-full min-[1400px]:w-auto min-[1400px]:max-w-none"
            style={{ aspectRatio: "1052 / 1340" }}
          >
            <picture className="block h-full">
              <source
                srcSet={`${asset("/media/reframer/filters-384.webp")} 384w, ${asset("/media/reframer/filters-768.webp")} 768w`}
                sizes="(max-width: 768px) 85vw, 330px"
                type="image/webp"
              />
              <img
                src={asset("/media/reframer/filters-384.webp")}
                alt="Reframer video filters panel"
                width={1052}
                height={1340}
                loading="lazy"
                decoding="async"
                className="w-full h-full object-contain"
              />
            </picture>
          </button>
        </div>

        <div className="flex flex-wrap items-center justify-center gap-4 sm:gap-6">
          <div className="flex items-center gap-2">
            <Apple className="w-4 h-4 text-[var(--text-tertiary)]" />
            <span className="text-[13px] text-[var(--text-tertiary)]">
              macOS 14+ (Sonoma)
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Gift className="w-4 h-4 text-[var(--success)]" />
            <span className="text-[13px] text-[var(--text-tertiary)]">
              Free during Beta
            </span>
          </div>
        </div>
      </section>

      {/* Lightbox Modal */}
      {lightbox && (
        <div
          ref={lightboxRef}
          role="dialog"
          aria-modal="true"
          aria-label={lightbox.type === "video" ? "Reframer demonstration video" : lightbox.alt}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md overflow-auto p-4 sm:p-8"
          onClick={closeLightbox}
          onKeyDown={handleDialogKeyDown}
        >
          <button
            ref={closeButtonRef}
            type="button"
            aria-label="Close media viewer"
            onClick={closeLightbox}
            className="fixed right-4 top-4 z-10 flex h-11 w-11 items-center justify-center rounded-full bg-black/70 text-white hover:bg-black sm:right-6 sm:top-6"
          >
            <X className="h-5 w-5" />
          </button>
          {lightbox.type === "video" ? (
            <video
              autoPlay
              loop
              muted
              playsInline
              className="h-auto max-h-[calc(100vh-2rem)] w-full max-w-[1440px] rounded-xl shadow-2xl"
              onClick={(e) => e.stopPropagation()}
            >
              <source src={lightbox.src} type="video/mp4" />
            </video>
          ) : (
            <Image
              src={lightbox.src}
              alt={lightbox.alt || ""}
              width={lightbox.src.includes("main-screen") ? 3648 : lightbox.src.includes("shortcuts") ? 973 : 1052}
              height={lightbox.src.includes("main-screen") ? 2350 : lightbox.src.includes("shortcuts") ? 1908 : 1340}
              className="h-auto max-h-[calc(100vh-2rem)] w-auto max-w-full rounded-xl shadow-2xl"
              onClick={(e) => e.stopPropagation()}
              unoptimized
            />
          )}
        </div>
      )}
    </>
  );
}

function FeaturesSection() {
  const features = [
    {
      icon: Layers,
      title: "Always On Top",
      description:
        "Video stays visible above all windows. Work in any app while keeping your reference in view.",
    },
    {
      icon: Frame,
      title: "Frame-Accurate",
      description:
        "Step through video frame by frame with keyboard shortcuts. Jump 10 frames with shift.",
    },
    {
      icon: MousePointerClick,
      title: "Click-Through Mode",
      description:
        "Lock the window and clicks pass through to apps below. Draw directly under the video overlay.",
    },
  ];

  return (
    <section
      id="features"
      className="flex flex-col items-center gap-10 px-4 py-16 sm:px-6 md:gap-16 md:py-[100px] lg:px-20 bg-[var(--bg-surface)]"
    >
      <div className="flex w-full max-w-[700px] flex-col items-center gap-4">
        <span className="text-xs font-medium text-[var(--accent-primary)] font-mono tracking-[2px]">
          FEATURES
        </span>
        <h2 className="text-3xl font-bold text-white text-center tracking-[-1px] sm:text-4xl md:text-5xl">
          Your reference, always in sight
        </h2>
        <p className="w-full max-w-[600px] text-base font-normal leading-[1.5] text-[var(--text-tertiary)] text-center md:text-lg">
          Reframer floats above all windows so you can work with video reference
          without switching apps.
        </p>
      </div>

      <div className="grid w-full max-w-[1100px] grid-cols-1 gap-5 md:grid-cols-3 md:gap-6">
        {features.map((feature, index) => (
          <div
            key={index}
            className="flex-1 flex flex-col gap-5 p-8 rounded-2xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
          >
            <div className="flex items-center justify-center w-12 h-12 rounded-xl bg-[var(--accent-tint)]">
              <feature.icon className="w-6 h-6 text-[var(--accent-primary)]" />
            </div>
            <h3 className="text-xl font-semibold text-white">{feature.title}</h3>
            <p className="text-[15px] text-[var(--text-tertiary)] leading-[1.6]">
              {feature.description}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}

function UseCasesSection() {
  const useCases = [
    {
      icon: PenTool,
      iconColor: "text-[var(--accent-primary)]",
      gradient: "from-[var(--bg-elevated)] to-[#FF5C0033]",
      title: "Animation & Rotoscoping",
      description:
        "Trace over video frames in your drawing app. Set opacity low, step through frames, and draw.",
    },
    {
      icon: LayoutGrid,
      iconColor: "text-[var(--success)]",
      gradient: "from-[var(--bg-elevated)] to-[#22C55E33]",
      title: "UI/UX Design",
      description:
        "Compare your designs with video prototypes. Overlay recordings to match transitions and timing.",
    },
    {
      icon: GraduationCap,
      iconColor: "text-[#6366F1]",
      gradient: "from-[var(--bg-elevated)] to-[#6366F133]",
      title: "Learning & Tutorials",
      description:
        "Follow along with video tutorials while working in the actual app. No more tab switching.",
    },
  ];

  return (
    <section className="flex flex-col items-center gap-10 px-4 py-16 sm:px-6 md:gap-16 md:py-[100px] lg:px-20 bg-[var(--bg-page)]">
      <div className="flex w-full max-w-[700px] flex-col items-center gap-4">
        <span className="text-xs font-medium text-[var(--accent-primary)] font-mono tracking-[2px]">
          USE CASES
        </span>
        <h2 className="text-3xl font-bold text-white text-center tracking-[-1px] sm:text-4xl md:text-5xl">
          Built for creative professionals
        </h2>
      </div>

      <div className="grid w-full max-w-[1100px] grid-cols-1 gap-5 md:grid-cols-3 md:gap-6">
        {useCases.map((useCase, index) => (
          <div
            key={index}
            className="flex min-h-[320px] flex-col rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] overflow-hidden"
          >
            <div
              className={`flex items-center justify-center h-[180px] bg-gradient-to-br ${useCase.gradient}`}
            >
              <useCase.icon className={`w-12 h-12 ${useCase.iconColor}`} />
            </div>
            <div className="flex flex-col gap-2 p-6">
              <h3 className="text-lg font-semibold text-white">
                {useCase.title}
              </h3>
              <p className="text-sm text-[var(--text-tertiary)] leading-[1.5]">
                {useCase.description}
              </p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function MoreFeaturesSection() {
  const moreFeatures = [
    {
      icon: SlidersHorizontal,
      title: "11 Video Filters",
      description:
        "Brightness, contrast, edges, line art, noir, and more. Chain filters together for custom effects.",
    },
    {
      icon: ZoomIn,
      title: "Zoom 10%-1000%",
      description:
        "Inspect details at any scale. Fine control with 0.1% precision using modifier keys.",
    },
    {
      icon: Eye,
      title: "Adjustable Opacity",
      description:
        "From 2% nearly invisible to 100% fully opaque. Find the perfect blend for any workflow.",
    },
    {
      icon: Keyboard,
      title: "Keyboard-First",
      description:
        "Full control without touching the mouse. Global shortcuts work from any app.",
    },
    {
      icon: Move,
      title: "Pan & Navigate",
      description:
        "Click and drag to pan. Arrow keys for pixel-precise movement. Reset instantly.",
    },
    {
      icon: Film,
      title: "All Major Formats",
      description:
        "MP4, MOV, AVI, M4V. H.264, H.265/HEVC, ProRes codecs supported.",
    },
  ];

  return (
    <section className="flex flex-col items-center gap-10 px-4 py-16 sm:px-6 md:gap-16 md:py-[100px] lg:px-20 bg-[var(--bg-surface)]">
      <div className="flex w-full max-w-[700px] flex-col items-center gap-4">
        <span className="text-xs font-medium text-[var(--accent-primary)] font-mono tracking-[2px]">
          CAPABILITIES
        </span>
        <h2 className="text-3xl font-bold text-white text-center tracking-[-1px] sm:text-4xl md:text-5xl">
          Powerful tools for precise control
        </h2>
      </div>

      <div className="flex w-full max-w-[1100px] flex-col gap-5">
        <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
          {moreFeatures.slice(0, 3).map((feature, index) => (
            <MoreFeatureCard key={index} feature={feature} />
          ))}
        </div>
        <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
          {moreFeatures.slice(3, 6).map((feature, index) => (
            <MoreFeatureCard key={index} feature={feature} />
          ))}
        </div>
      </div>
    </section>
  );
}

function MoreFeatureCard({
  feature,
}: {
  feature: {
    icon: React.ComponentType<{ className?: string }>;
    title: string;
    description: string;
  };
}) {
  return (
    <div className="flex-1 flex gap-4 p-6 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]">
      <div className="flex items-center justify-center w-10 h-10 rounded-[10px] bg-[var(--accent-tint)] shrink-0">
        <feature.icon className="w-5 h-5 text-[var(--accent-primary)]" />
      </div>
      <div className="flex flex-col gap-1.5">
        <h3 className="text-base font-semibold text-white">{feature.title}</h3>
        <p className="text-sm text-[var(--text-tertiary)] leading-[1.5]">
          {feature.description}
        </p>
      </div>
    </div>
  );
}

function CTASection() {
  return (
    <section className="flex flex-col items-center gap-8 px-4 py-16 sm:px-6 md:py-[100px] lg:px-20 bg-gradient-to-b from-[var(--bg-page)] to-[var(--bg-elevated)]">
      <div className="flex w-full max-w-[700px] flex-col items-center gap-6">
        <h2 className="text-3xl font-bold text-white text-center tracking-[-1px] sm:text-4xl md:text-5xl">
          Ready to reframe your workflow?
        </h2>
        <p className="text-lg text-[var(--text-tertiary)] text-center">
          Download the beta for free. macOS 14+ required.
        </p>

        <div className="flex w-full flex-col items-stretch gap-3 sm:w-auto sm:flex-row sm:items-center sm:gap-4">
          <a href="https://contra.com/products/UBCf87LD-reframer" target="_blank" rel="noopener noreferrer" data-forge-action="product_listing" className="flex items-center gap-2.5 px-8 py-4 rounded-[10px] bg-gradient-to-br from-[var(--accent-primary)] to-[var(--accent-light)] text-[#171719] font-semibold hover:opacity-90 transition-opacity">
            <Download className="w-5 h-5" />
            <span>Download for macOS</span>
          </a>
          <Link
            href={asset("/docs")}
            className="flex items-center gap-2.5 px-8 py-4 rounded-[10px] border border-[var(--border-default)] text-[var(--text-secondary)] font-medium hover:border-[var(--text-tertiary)] transition-colors"
          >
            <BookOpen className="w-5 h-5" />
            <span>Read Documentation</span>
          </Link>
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="flex flex-col gap-10 px-4 py-12 sm:px-6 md:py-[60px] lg:px-20 bg-[var(--bg-surface)]">
      <div className="flex w-full flex-col gap-10 md:flex-row md:justify-between">
        <div className="flex w-full max-w-[300px] flex-col gap-4">
          <Link href={asset("/")} className="flex items-center gap-2.5">
            <div className="w-7 h-7 rounded-md overflow-hidden">
              <Image
                src={asset("/media/reframer/icon-64.webp")}
                alt=""
                width={28}
                height={28}
                className="w-full h-full object-cover"
              />
            </div>
            <span className="text-base font-bold text-white tracking-[1px]">
              Reframer
            </span>
          </Link>
          <p className="w-full max-w-[280px] text-sm leading-[1.5] text-[var(--text-tertiary)]">
            Transparent video overlay for macOS. Perfect for animation reference
            and creative work.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-10 sm:grid-cols-3 md:gap-12 lg:gap-20">
          <FooterColumn
            title="Product"
            links={[
              { label: "Features", href: "#features" },
              { label: "Download", href: "https://contra.com/products/UBCf87LD-reframer", action: "product_listing" },
              { label: "Changelog", href: asset("/changelog") },
            ]}
          />
          <FooterColumn
            title="Resources"
            links={[
              { label: "Documentation", href: asset("/docs") },
              { label: "Keyboard Shortcuts", href: asset("/docs/keyboard-shortcuts") },
              { label: "GitHub", href: "https://github.com/ivg-design/reframer", action: "repository" },
            ]}
          />
          <FooterColumn
            title="Explore"
            links={[
              { label: "All creative tools", href: "/" },
              { label: "Work with me", href: "/services/" },
            ]}
          />
        </div>
      </div>

      <div className="pt-6">
        <div className="w-full h-px bg-[var(--border-subtle)]" />
      </div>

      <div className="flex w-full flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <span className="text-[13px] text-[var(--text-disabled)]">
          &copy; 2026 IVG-Design. All rights reserved.
        </span>
        <span className="text-xs text-[var(--text-disabled)] font-mono">
          Version 0.8.1-beta.3
        </span>
      </div>
    </footer>
  );
}

function FooterColumn({
  title,
  links,
}: {
  title: string;
  links: { label: string; href: string; action?: "repository" | "service_outbound" | "product_listing" }[];
}) {
  return (
    <div className="flex flex-col gap-4">
      <span className="text-xs font-semibold text-[var(--text-secondary)] tracking-[1px]">
        {title}
      </span>
      {links.map((link, index) => (
        <Link
          key={index}
          href={link.href}
          data-forge-action={link.action}
          className="text-sm text-[var(--text-tertiary)] hover:text-white transition-colors"
        >
          {link.label}
        </Link>
      ))}
    </div>
  );
}
