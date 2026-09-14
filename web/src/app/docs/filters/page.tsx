import {
  DocsLayout,
  DocsSection,
  DocsParagraph,
  DocsTable,
  DocsNextSteps,
  Kbd,
} from "@/components/DocsLayout";
import { createPageMetadata } from "@/lib/seo";

export const metadata = createPageMetadata({
  title: "Filters | Reframer Docs",
  description:
    "Explore all 11 real-time Reframer filters, including chaining workflows and advanced filter controls.",
  path: "/docs/filters",
});

export default function FiltersPage() {
  return (
    <DocsLayout
      title="Filters"
      description="Apply real-time video filters to enhance your reference material."
      breadcrumb="Filters"
    >
      <DocsSection title="Overview">
        <DocsParagraph>
          Reframer includes 11 real-time video filters that can be applied and combined.
          Unlike single-filter applications, Reframer allows you to chain multiple filters
          to create exactly the effect you need for your workflow.
        </DocsParagraph>
      </DocsSection>

      <DocsSection title="Available Filters">
        <DocsTable
          headers={["Filter", "Description"]}
          rows={[
            ["Brightness", "Adjust overall lightness (-100% to +100%)"],
            ["Contrast", "Increase or decrease tonal range"],
            ["Saturation", "Control color intensity (0% = grayscale)"],
            ["Exposure", "Adjust exposure in EV stops"],
            ["Edges", "Edge detection for tracing workflows"],
            ["Sharpen", "Enhance edge sharpness"],
            ["Unsharp Mask", "Professional sharpening with radius control"],
            ["Monochrome", "Sepia/tint effect with customizable color"],
            ["Invert", "Invert all colors"],
            ["Line Art", "Clean line drawing effect (great for tracing)"],
            ["Noir", "Black & white film effect"],
          ]}
        />
      </DocsSection>

      <DocsSection title="Using Filters">
        <DocsParagraph>
          Access filters through the filter button in the toolbar:
        </DocsParagraph>
        <DocsTable
          headers={["Action", "How"]}
          rows={[
            ["Open filter panel", <><>Click filter icon or press </><Kbd>F</Kbd></>],
            ["Quick cycle filters", "Click the filter button to cycle through"],
            ["Filter menu", "Hold the filter button to see all options"],
            ["Toggle a filter", "Click the filter checkbox in panel"],
            ["Adjust intensity", "Drag the slider (where available)"],
            ["Reset all filters", "Click 'Reset' in filter panel"],
            ["Close filter panel", <Kbd key="esc">Esc</Kbd>],
          ]}
        />
      </DocsSection>

      <DocsSection title="Quick Filters vs Advanced">
        <DocsParagraph>
          <strong>Quick Filters</strong> (available in dropdown):
        </DocsParagraph>
        <div className="flex flex-col gap-2 pl-4 mb-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Brightness, Contrast, Saturation, Exposure, Edges, Sharpen, Invert, Noir
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Single slider control for easy adjustment
            </span>
          </div>
        </div>

        <DocsParagraph>
          <strong>Advanced Filters</strong> (filter panel only):
        </DocsParagraph>
        <div className="flex flex-col gap-2 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Unsharp Mask, Monochrome, Line Art
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              Multiple parameters for fine-tuned control
            </span>
          </div>
        </div>
      </DocsSection>

      <DocsSection title="Combining Filters">
        <DocsParagraph>
          Filters can be chained together. Some useful combinations:
        </DocsParagraph>
        <div className="flex flex-col gap-3 pl-4">
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Edges + Brightness</strong> — Make edges more visible against dark backgrounds
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Line Art + Contrast</strong> — Get cleaner line drawings for tracing
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Saturation (0%) + Brightness</strong> — High-contrast grayscale reference
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Sharpen + Edges</strong> — Enhanced edge detail for precise tracing
            </span>
          </div>
          <div className="flex gap-3">
            <span className="text-sm text-[var(--text-tertiary)]">•</span>
            <span className="text-sm text-[var(--text-secondary)]">
              <strong>Monochrome + Contrast</strong> — Sepia-toned reference with improved clarity
            </span>
          </div>
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
            href: "/docs/zoom-pan",
            title: "Zoom & Pan",
            description: "Inspect filtered details",
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
