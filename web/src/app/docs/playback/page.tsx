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
  title: "Playback Controls | Reframer Docs",
  description:
    "Use frame stepping, timeline scrubbing, and global shortcuts for frame-accurate playback in Reframer.",
  path: "/docs/playback",
});

export default function PlaybackPage() {
  return (
    <DocsLayout
      title="Playback Controls"
      description="Navigate through video with frame-accurate precision."
      breadcrumb="Playback Controls"
    >
      <DocsSection title="Play and Pause">
        <DocsTable
          headers={["Method", "Action"]}
          rows={[
            ["Keyboard", <KeyCombo key="space" keys="Space" />],
            ["Control bar", "Click the play/pause button"],
          ]}
        />
      </DocsSection>

      <DocsSection title="Frame Stepping">
        <DocsParagraph>Move through video one frame at a time for precise positioning.</DocsParagraph>
        <DocsTable
          headers={["Action", "Method"]}
          rows={[
            ["Step frames", <><ScrollWheel /> on video</>],
            ["Previous frame", <><Kbd>⌘</Kbd> <Kbd wide>Page Up</Kbd> (global)</>],
            ["Next frame", <><Kbd>⌘</Kbd> <Kbd wide>Page Down</Kbd> (global)</>],
            ["Back 10 frames", <><Kbd>⌘</Kbd><Kbd>⇧</Kbd> <Kbd wide>Page Up</Kbd> (global)</>],
            ["Forward 10 frames", <><Kbd>⌘</Kbd><Kbd>⇧</Kbd> <Kbd wide>Page Down</Kbd> (global)</>],
          ]}
        />
      </DocsSection>

      <DocsSection title="Timeline Scrubbing">
        <DocsParagraph>
          Drag the timeline slider to jump to any point in the video.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Frame Input">
        <DocsParagraph>For precise navigation, type the exact frame number:</DocsParagraph>
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">1.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Click the frame counter in the control bar
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">2.</span>
            <span className="text-sm text-[var(--text-secondary)]">Type the frame number</span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm font-semibold text-[var(--accent-primary)]">3.</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Press <KeyCombo keys="Enter" /> to jump to that frame
            </span>
          </div>
        </div>
        <DocsParagraph>
          Arrow keys while focused: <Kbd>↑</Kbd>/<Kbd>↓</Kbd> step by 1 frame, <Kbd>⇧</Kbd> + arrows step by 10 frames.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Global Shortcuts">
        <DocsParagraph>These work even when Reframer isn&apos;t the active app:</DocsParagraph>
        <DocsTable
          headers={["Action", "Shortcut"]}
          rows={[
            ["Previous frame", <><Kbd>⌘</Kbd> <Kbd wide>Page Up</Kbd></>],
            ["Next frame", <><Kbd>⌘</Kbd> <Kbd wide>Page Down</Kbd></>],
            ["Back 10 frames", <><Kbd>⌘</Kbd><Kbd>⇧</Kbd> <Kbd wide>Page Up</Kbd></>],
            ["Forward 10 frames", <><Kbd>⌘</Kbd><Kbd>⇧</Kbd> <Kbd wide>Page Down</Kbd></>],
          ]}
        />
      </DocsSection>

      <DocsSection title="Audio">
        <DocsTable
          headers={["Action", "Method"]}
          rows={[
            ["Toggle mute", "Click the speaker icon"],
            ["Adjust volume", "Drag the volume slider"],
          ]}
        />
        <DocsParagraph>Audio is muted by default to avoid interrupting your work.</DocsParagraph>
      </DocsSection>

      <DocsNextSteps
        links={[
          {
            href: "/docs/zoom-pan",
            title: "Zoom & Pan",
            description: "Inspect video details",
          },
          {
            href: "/docs/opacity",
            title: "Opacity",
            description: "Blend with your workspace",
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
