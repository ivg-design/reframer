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
  title: "Keyboard Shortcuts | Reframer Docs",
  description:
    "Complete keyboard reference for Reframer, including playback, zoom, pan, lock mode, and global shortcuts.",
  path: "/docs/keyboard-shortcuts",
});

export default function KeyboardShortcutsPage() {
  return (
    <DocsLayout
      title="Keyboard Shortcuts"
      description="Complete reference for all keyboard controls."
      breadcrumb="Keyboard Shortcuts"
    >
      <DocsSection title="Overview">
        <DocsParagraph>
          Reframer is designed for keyboard-driven workflows. Arrow keys pan the video,
          scroll wheel steps frames, and scroll with modifiers controls zoom.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="File">
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[[<KeyCombo key="o" keys="⌘ O" />, "Open video file"]]}
        />
      </DocsSection>

      <DocsSection title="Playback">
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<KeyCombo key="space" keys="Space" />, "Play / Pause"],
          ]}
        />
        <DocsParagraph>
          Frame stepping is available via <ScrollWheel /> on video or global shortcuts (see below).
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Pan (Arrow Keys)">
        <DocsParagraph>When unlocked, arrow keys pan the video:</DocsParagraph>
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<>Arrow Keys</>, "Pan 1 pixel"],
            [<><Kbd>⇧</Kbd> + Arrow Keys</>, "Pan 10 pixels"],
            [<><Kbd>⇧</Kbd><Kbd>⌘</Kbd> + Arrow Keys</>, "Pan 100 pixels"],
          ]}
        />
      </DocsSection>

      <DocsSection title="View">
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<Kbd key="zero">0</Kbd>, "Reset to 100%"],
            [<Kbd key="r">R</Kbd>, "Reset zoom and pan"],
          ]}
        />
        <DocsParagraph>
          Zoom is controlled via <ScrollWheel /> with modifiers (see Mouse Controls).
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Window">
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<Kbd key="l">L</Kbd>, "Toggle lock mode"],
            [<><Kbd>H</Kbd> or <Kbd>?</Kbd></>, "Show shortcuts panel"],
            [<KeyCombo key="esc" keys="Esc" />, "Close panel"],
          ]}
        />
        <DocsParagraph>
          Access full documentation via <strong>Help → Reframer Documentation</strong> in the menu bar.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Filters">
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<Kbd key="f">F</Kbd>, "Toggle filter panel"],
            [<KeyCombo key="esc2" keys="Esc" />, "Close filter panel"],
          ]}
        />
      </DocsSection>

      <DocsSection title="Input Fields">
        <DocsParagraph>When a numeric field (frame, zoom, opacity) is focused:</DocsParagraph>
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<><Kbd>↑</Kbd> / <Kbd>↓</Kbd></>, "Increment / decrement by 1"],
            [<><Kbd>⇧</Kbd> + <Kbd>↑</Kbd> / <Kbd>↓</Kbd></>, "Increment / decrement by 10"],
            [<><Kbd>⌘</Kbd> + <Kbd>↑</Kbd> / <Kbd>↓</Kbd></>, "Increment / decrement by 0.1"],
            [<KeyCombo key="ca" keys="⌘ A" />, "Select all"],
            [<><KeyCombo key="enter" keys="Enter" /> or <KeyCombo key="esc3" keys="Esc" /></>, "Apply and defocus"],
          ]}
        />
        <div className="p-4 rounded-lg bg-[var(--bg-elevated)] border border-[var(--border-subtle)]">
          <p className="text-sm text-[var(--text-secondary)]">
            <strong>Note:</strong> Arrow keys only adjust values when an input field is focused. Outside input fields, arrow keys pan the video.
          </p>
        </div>
      </DocsSection>

      <DocsSection title="Global Shortcuts (Lock Mode)">
        <DocsParagraph>
          These work when Reframer is locked, even if it isn&apos;t the active app:
        </DocsParagraph>
        <DocsTable
          headers={["Shortcut", "Action"]}
          rows={[
            [<KeyCombo key="csl" keys="⌘ ⇧ L" />, "Toggle lock"],
            [<><Kbd>⌘</Kbd> <Kbd wide>Page Up</Kbd></>, "Previous frame"],
            [<><Kbd>⌘</Kbd> <Kbd wide>Page Down</Kbd></>, "Next frame"],
            [<><Kbd>⌘</Kbd><Kbd>⇧</Kbd> <Kbd wide>Page Up</Kbd></>, "Back 10 frames"],
            [<><Kbd>⌘</Kbd><Kbd>⇧</Kbd> <Kbd wide>Page Down</Kbd></>, "Forward 10 frames"],
          ]}
        />
      </DocsSection>

      <DocsSection title="Mouse Controls">
        <DocsParagraph>When the window is unlocked:</DocsParagraph>
        <DocsTable
          headers={["Control", "Action"]}
          rows={[
            ["Drag from center", "Move window"],
            ["Drag edges / corners", "Resize window"],
            ["Click + drag on video", "Pan video"],
            [<><ScrollWheel /> on video</>, "Step frames"],
            [<><Kbd>⇧</Kbd> + <ScrollWheel /></>, "Zoom (5% steps)"],
            [<><Kbd>⌘</Kbd><Kbd>⇧</Kbd> + <ScrollWheel /></>, "Fine zoom (0.1% steps)"],
          ]}
        />
      </DocsSection>

      <DocsNextSteps
        links={[
          {
            href: "/docs/playback",
            title: "Playback Controls",
            description: "Learn frame-accurate navigation",
          },
          {
            href: "/docs/filters",
            title: "Filters",
            description: "Apply real-time video effects",
          },
          {
            href: "/docs/lock-mode",
            title: "Lock Mode",
            description: "Click through to apps below",
          },
        ]}
      />
    </DocsLayout>
  );
}
