export default function AnswerSection() {
  return (
    <section className="flex flex-col items-center px-4 py-16 sm:px-6 lg:px-20 bg-[var(--bg-surface)] border-y border-[var(--border-subtle)]">
      <div className="flex w-full max-w-[1100px] flex-col gap-8">
        <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--bg-elevated)] p-8">
          <p className="text-xs uppercase tracking-[0.14em] text-[var(--accent-primary)] font-semibold mb-3">
            Why I Made This?
          </p>
          <h2 className="text-4xl font-bold text-white tracking-[-1px] mb-4">What is Reframer?</h2>
          <p className="text-[17px] text-[var(--text-tertiary)] leading-[1.7]">
            Reframer is a transparent video overlay app for macOS. It keeps reference footage visible
            above your workspace so you can animate, design, or study motion without constant window switching.
          </p>
        </div>

        <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--bg-elevated)] overflow-x-auto">
          <table className="w-full min-w-[760px] text-left">
            <caption className="sr-only">Reframer workflow metrics</caption>
            <thead>
              <tr className="border-b border-[var(--border-subtle)]">
                <th className="px-5 py-4 text-sm font-semibold text-[var(--text-secondary)]">Metric</th>
                <th className="px-5 py-4 text-sm font-semibold text-[var(--text-secondary)]">Value</th>
                <th className="px-5 py-4 text-sm font-semibold text-[var(--text-secondary)]">Why it matters</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-[var(--border-subtle)]">
                <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">Video filters</td>
                <td className="px-5 py-4 text-sm text-white">11</td>
                <td className="px-5 py-4 text-sm text-[var(--text-tertiary)]">Supports tracing, contrast tuning, and reference cleanup.</td>
              </tr>
              <tr className="border-b border-[var(--border-subtle)]">
                <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">Zoom range</td>
                <td className="px-5 py-4 text-sm text-white">10% to 1000%</td>
                <td className="px-5 py-4 text-sm text-[var(--text-tertiary)]">Enables both full-frame and detail-level analysis.</td>
              </tr>
              <tr className="border-b border-[var(--border-subtle)]">
                <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">Opacity range</td>
                <td className="px-5 py-4 text-sm text-white">2% to 100%</td>
                <td className="px-5 py-4 text-sm text-[var(--text-tertiary)]">Balances overlay visibility with app interaction below.</td>
              </tr>
              <tr>
                <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">Supported platform</td>
                <td className="px-5 py-4 text-sm text-white">macOS 14+</td>
                <td className="px-5 py-4 text-sm text-[var(--text-tertiary)]">Focused native workflow for modern Mac systems.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
