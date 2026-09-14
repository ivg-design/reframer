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
  title: "Opacity Controls | Reframer Docs",
  description:
    "Adjust Reframer opacity from 2% to 100% for tracing, timing, and side-by-side visual comparison workflows.",
  path: "/docs/opacity",
});

export default function OpacityPage() {
  return (
    <DocsLayout
      title="Opacity"
      description="Blend the video overlay with your workspace."
      breadcrumb="Opacity"
    >
      <DocsSection title="Overview">
        <DocsParagraph>
          Adjust the video transparency to see both the reference footage and your work underneath.
          Lower opacity makes the video more transparent; higher opacity makes it more solid.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Adjusting Opacity">
        <DocsParagraph>
          <strong>Slider</strong>
        </DocsParagraph>
        <DocsParagraph>
          Drag the opacity slider in the control bar. The slider ranges from nearly transparent
          (2%) to fully opaque (100%).
        </DocsParagraph>

        <DocsParagraph>
          <strong>Numeric Input</strong>
        </DocsParagraph>
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">1.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Click the percentage value next to the slider
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">2.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Type your desired opacity (2-100)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">3.</span>
            <span className="text-sm text-[var(--text-secondary)]">Press <KeyCombo keys="Enter" /> to confirm</span>
          </div>
        </div>
        <DocsParagraph>
          Arrow keys while focused: <Kbd>↑</Kbd>/<Kbd>↓</Kbd> step by 1%, <Kbd>⇧</Kbd> + arrows step by 10%, <Kbd>⌘</Kbd> + arrows step by 0.1%.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Opacity Range">
        <DocsTable
          headers={["Value", "Use Case"]}
          rows={[
            ["2-10%", "Barely visible guide lines"],
            ["20-40%", "Light tracing reference"],
            ["50-70%", "Balanced overlay for comparison"],
            ["80-90%", "Solid reference with slight transparency"],
            ["100%", "Fully opaque (no transparency)"],
          ]}
        />
      </DocsSection>

      <DocsSection title="Use Cases">
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Tracing</strong> — Set to 20-40% so you can draw while seeing your strokes
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Timing reference</strong> — Use 60-80% to match animation timing
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Design comparison</strong> — Toggle between 50% and 100% to compare layouts
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Tutorial following</strong> — Keep at 70-90% to see instructions clearly
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsNextSteps
        links={[
          {
            href: "/docs/filters",
            title: "Filters",
            description: "Apply visual effects",
          },
          {
            href: "/docs/lock-mode",
            title: "Lock Mode",
            description: "Click through to apps",
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
