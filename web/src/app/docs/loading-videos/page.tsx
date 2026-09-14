import {
  DocsLayout,
  DocsSection,
  DocsParagraph,
  DocsTable,
  DocsNextSteps,
  KeyCombo,
} from "@/components/DocsLayout";
import { createPageMetadata } from "@/lib/seo";

export const metadata = createPageMetadata({
  title: "Loading Videos | Reframer Docs",
  description:
    "Learn supported formats, codecs, and best practices for loading videos in Reframer.",
  path: "/docs/loading-videos",
});

export default function LoadingVideosPage() {
  return (
    <DocsLayout
      title="Loading Videos"
      description="Open video files for overlay display."
      breadcrumb="Loading Videos"
    >
      <DocsSection title="Overview">
        <DocsParagraph>
          Reframer uses macOS native AVFoundation for video playback, ensuring smooth
          performance and broad format compatibility. Load videos by drag-and-drop,
          file picker, or keyboard shortcut.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Supported Formats">
        <DocsTable
          headers={["Format", "Extensions"]}
          rows={[
            ["MPEG-4", ".mp4, .m4v"],
            ["QuickTime", ".mov"],
            ["AVI", ".avi"],
            ["MPEG", ".mpeg, .mpg, .m2v"],
            ["Transport Stream", ".ts, .mts, .m2ts"],
            ["3GPP", ".3gp, .3g2"],
          ]}
        />
      </DocsSection>

      <DocsSection title="Supported Codecs">
        <DocsParagraph>The following codecs are supported via AVFoundation:</DocsParagraph>
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>H.264 / AVC</strong> — Universal compatibility
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>H.265 / HEVC</strong> — High efficiency, smaller files
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Apple ProRes</strong> — All variants (422, 4444, LT, Proxy, HQ)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>AV1</strong> — Next-gen codec (macOS 13+)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>MPEG-2</strong> — Legacy broadcast format
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsSection title="Loading Methods">
        <DocsTable
          headers={["Method", "How"]}
          rows={[
            ["Drag and drop", "Drop video file onto Reframer window"],
            ["File picker", <><>File → Open or </><KeyCombo keys="⌘ O" /></>],
            ["Recent files", "File → Open Recent"],
          ]}
        />
      </DocsSection>

      <DocsSection title="After Loading">
        <DocsParagraph>When a video loads successfully:</DocsParagraph>
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Video displays at its native aspect ratio
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Playback controls become active
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Frame counter shows total frames
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Video starts paused at frame 0
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsSection title="Troubleshooting">
        <DocsParagraph>
          <strong>Video won&apos;t load?</strong>
        </DocsParagraph>
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Check the file format is supported
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Ensure the file isn&apos;t corrupted
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Try converting to MP4 with H.264 codec
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsNextSteps
        links={[
          {
            href: "/docs/getting-started",
            title: "Getting Started",
            description: "Basic setup guide",
          },
          {
            href: "/docs/playback",
            title: "Playback Controls",
            description: "Navigate your video",
          },
          {
            href: "/docs/keyboard-shortcuts",
            title: "Keyboard Shortcuts",
            description: "View all shortcuts",
          },
        ]}
      />
    </DocsLayout>
  );
}
