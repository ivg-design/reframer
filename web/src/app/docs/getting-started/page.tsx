import {
  DocsLayout,
  DocsSection,
  DocsParagraph,
  DocsTable,
  DocsNextSteps,
  KeyCombo,
  Kbd,
  ScrollWheel,
} from "@/components/DocsLayout";
import { createPageMetadata } from "@/lib/seo";

export const metadata = createPageMetadata({
  title: "Getting Started | Reframer Docs",
  description: "Install Reframer on macOS and load your first video overlay in minutes.",
  path: "/docs/getting-started",
});

export default function GettingStartedPage() {
  return (
    <DocsLayout
      title="Getting Started"
      description="Install Reframer and load your first video overlay."
      breadcrumb="Getting Started"
    >
      <DocsSection title="Installation">
        <DocsParagraph>
          Move Reframer.app to your Applications folder. On first launch, the app will prompt
          to move itself if it&apos;s not already there.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="First Launch">
        <DocsParagraph>When you first launch Reframer:</DocsParagraph>
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">1.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              A transparent window appears with a drop zone
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">2.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              The control bar floats at the bottom of the screen
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">3.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Drop a video file or press <KeyCombo keys="⌘ O" /> to open one
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsSection title="Loading a Video">
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Drag and drop</strong> — Drop a video file onto the window
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Click the drop zone</strong> — Opens a file picker
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Keyboard</strong> — Press <KeyCombo keys="⌘ O" /> to open a file
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsSection title="Basic Controls">
        <DocsTable
          headers={["Action", "Control"]}
          rows={[
            ["Play / Pause", <><KeyCombo key="space" keys="Space" /> or click play button</>],
            ["Step frames", <><ScrollWheel /> on video</>],
            ["Pan", <>Arrow Keys or click and drag</>],
            ["Zoom", <><Kbd>⇧</Kbd> + <ScrollWheel /></>],
            ["Adjust opacity", "Drag the opacity slider"],
            ["Lock window", <><Kbd>L</Kbd> or click lock icon</>],
          ]}
        />
      </DocsSection>

      <DocsSection title="Window Behavior">
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Has no title bar or buttons (transparent and frameless)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Floats above all other windows by default
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Drag from center to move (when unlocked)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Drag edges or corners to resize (when unlocked)
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsNextSteps
        links={[
          {
            href: "/docs/loading-videos",
            title: "Loading Videos",
            description: "Supported formats and codecs",
          },
          {
            href: "/docs/playback",
            title: "Playback Controls",
            description: "Frame-accurate navigation",
          },
          {
            href: "/docs/keyboard-shortcuts",
            title: "Keyboard Shortcuts",
            description: "Complete shortcut reference",
          },
        ]}
      />
    </DocsLayout>
  );
}
