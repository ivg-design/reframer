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
  title: "Zoom and Pan | Reframer Docs",
  description:
    "Inspect reference footage with precision zoom and pan controls, including keyboard and fine-step shortcuts.",
  path: "/docs/zoom-pan",
});

export default function ZoomPanPage() {
  return (
    <DocsLayout
      title="Zoom & Pan"
      description="Inspect video details at any magnification."
      breadcrumb="Zoom & Pan"
    >
      <DocsSection title="Zooming">
        <DocsParagraph>
          <strong>Scroll Wheel</strong> (when the window is unlocked):
        </DocsParagraph>
        <DocsTable
          headers={["Action", "Gesture"]}
          rows={[
            ["Zoom (5% steps)", <><Kbd>⇧</Kbd> + <ScrollWheel /></>],
            ["Fine zoom (0.1% steps)", <><Kbd>⌘</Kbd><Kbd>⇧</Kbd> + <ScrollWheel /></>],
          ]}
        />
        <DocsParagraph>
          <strong>Reset</strong>
        </DocsParagraph>
        <DocsTable
          headers={["Action", "Shortcut"]}
          rows={[
            ["Reset to 100%", <Kbd>0</Kbd>],
            ["Reset zoom and pan", <Kbd>R</Kbd>],
          ]}
        />
      </DocsSection>

      <DocsSection title="Zoom Input">
        <DocsParagraph>For precise control, type the exact zoom percentage:</DocsParagraph>
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">1.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Click the zoom field in the control bar (shows 100%)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">2.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Type your desired percentage (10–1000)
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">3.</span>
            <span className="text-sm text-[var(--text-secondary)]">Press <KeyCombo keys="Enter" /></span>
          </div>
        </div>
        <DocsParagraph>
          Arrow keys while focused: <Kbd>↑</Kbd>/<Kbd>↓</Kbd> step by 1%, <Kbd>⇧</Kbd> + arrows step by 10%, <Kbd>⌘</Kbd> + arrows step by 0.1%.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Panning">
        <DocsParagraph>
          <strong>Mouse:</strong> Click and drag anywhere on the video to pan. This works at any zoom level.
        </DocsParagraph>
        <DocsParagraph>
          <strong>Keyboard</strong> (when unlocked):
        </DocsParagraph>
        <DocsTable
          headers={["Action", "Shortcut"]}
          rows={[
            ["Pan 1 pixel", <>Arrow Keys</>],
            ["Pan 10 pixels", <><Kbd>⇧</Kbd> + Arrow Keys</>],
            ["Pan 100 pixels", <><Kbd>⇧</Kbd><Kbd>⌘</Kbd> + Arrow Keys</>],
          ]}
        />
      </DocsSection>

      <DocsSection title="Zoom Display">
        <DocsParagraph>
          The overlay in the upper-right corner shows current zoom (e.g., 125%). This appears when
          zoomed above or below 100%.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Reset View">
        <DocsTable
          headers={["Action", "Method"]}
          rows={[
            ["Reset zoom only", <Kbd>0</Kbd>],
            ["Reset zoom and pan", <><Kbd>R</Kbd> or click ↺</>],
          ]}
        />
        <div className="p-4 rounded-lg bg-[var(--bg-elevated)] border border-[var(--border-subtle)]">
          <p className="text-sm text-[var(--text-secondary)]">
            <strong>Tip:</strong> Use fine zoom (<Kbd>⌘</Kbd><Kbd>⇧</Kbd> + <ScrollWheel />) for 0.1% precision when matching exact scales.
          </p>
        </div>
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
