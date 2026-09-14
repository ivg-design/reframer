import {
  DocsLayout,
  DocsSection,
  DocsParagraph,
  DocsTable,
  DocsNextSteps,
  KeyCombo,
  Kbd,
} from "@/components/DocsLayout";
import { createPageMetadata } from "@/lib/seo";

export const metadata = createPageMetadata({
  title: "Lock Mode | Reframer Docs",
  description:
    "Use Reframer lock mode to pass clicks through the overlay and interact with apps beneath the video layer.",
  path: "/docs/lock-mode",
});

export default function LockModePage() {
  return (
    <DocsLayout
      title="Lock Mode"
      description="Click through the video to interact with apps below."
      breadcrumb="Lock Mode"
    >
      <DocsSection title="Toggling Lock Mode">
        <DocsTable
          headers={["Method", "Action"]}
          rows={[
            ["Keyboard", <Kbd key="l">L</Kbd>],
            ["Control bar", "Click the lock icon"],
            ["Global shortcut", <><Kbd>⌘</Kbd><Kbd>⇧</Kbd><Kbd>L</Kbd> (works from any app)</>],
          ]}
        />
      </DocsSection>

      <DocsSection title="What Lock Mode Does">
        <DocsParagraph>
          <strong>When Locked:</strong>
        </DocsParagraph>
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Clicks pass through the video to apps below
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Window cannot be moved or resized
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">Zoom and pan are disabled</span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">Control bar remains interactive</span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">A lock indicator appears in the corner</span>
          </div>
        </div>

        <DocsParagraph>
          <strong>When Unlocked:</strong>
        </DocsParagraph>
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Video responds to mouse interaction
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">Window can be moved and resized</span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">Zoom, pan, and scroll controls work</span>
          </div>
        </div>
      </DocsSection>

      <DocsSection title="Workflow Tips">
        <DocsParagraph>
          <strong>For Drawing/Tracing:</strong>
        </DocsParagraph>
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">1.</span>
            <span className="text-sm text-[var(--text-secondary)]">Position the video where you want it</span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">2.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Set your desired opacity (30-50% works well)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">3.</span>
            <span className="text-sm text-[var(--text-secondary)]">Press <Kbd>L</Kbd> to lock</span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">4.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Draw in your app — clicks go through the video
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">5.</span>
            <span className="text-sm text-[var(--text-secondary)]">Press <Kbd>L</Kbd> again to unlock and reposition</span>
          </div>
        </div>

        <DocsParagraph>
          <strong>Quick Toggle:</strong> The global shortcut <Kbd>⌘</Kbd><Kbd>⇧</Kbd><Kbd>L</Kbd> lets you toggle lock from any app
          without switching to Reframer first.
        </DocsParagraph>
      </DocsSection>

      <DocsNextSteps
        links={[
          {
            href: "/docs/opacity",
            title: "Opacity",
            description: "Blend with your workspace",
          },
          {
            href: "/docs/filters",
            title: "Filters",
            description: "Apply visual effects",
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
