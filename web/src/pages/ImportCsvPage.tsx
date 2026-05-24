import { useState, useRef } from 'react'
import { Link } from 'react-router-dom'
import { api, ApiError, type CSVPreviewRow, type CSVPreviewResult, type CSVImportResult } from '../lib/api'

type Step = 'upload' | 'preview' | 'done'

export default function ImportCsvPage() {
  const [step, setStep] = useState<Step>('upload')
  const [file, setFile] = useState<File | null>(null)
  const [previewing, setPreviewing] = useState(false)
  const [preview, setPreview] = useState<CSVPreviewResult | null>(null)
  const [previewError, setPreviewError] = useState<string | null>(null)
  const [importing, setImporting] = useState(false)
  const [result, setResult] = useState<CSVImportResult | null>(null)
  const [importError, setImportError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  async function handlePreview() {
    if (!file) return
    setPreviewing(true)
    setPreviewError(null)
    try {
      const r = await api.csvPreview(file)
      setPreview(r)
      setStep('preview')
    } catch (e) {
      setPreviewError(e instanceof ApiError ? e.message : 'Preview failed')
    } finally {
      setPreviewing(false)
    }
  }

  async function handleImport() {
    if (!preview) return
    setImporting(true)
    setImportError(null)
    try {
      const ids = preview.rows.filter(r => !r.already_owned).map(r => r.bgg_id)
      const r = await api.csvImport(ids)
      setResult(r)
      setStep('done')
    } catch (e) {
      setImportError(e instanceof ApiError ? e.message : 'Import failed')
    } finally {
      setImporting(false)
    }
  }

  function reset() {
    setStep('upload')
    setFile(null)
    setPreview(null)
    setPreviewError(null)
    setResult(null)
    setImportError(null)
    if (fileRef.current) fileRef.current.value = ''
  }

  const newRows = preview?.rows.filter(r => !r.already_owned) ?? []

  return (
    <div className="flex flex-col gap-5">
      {/* Header */}
      <div className="flex items-center gap-3 pt-1">
        <Link to="/import" className="text-accent text-[1.4rem] leading-none no-underline">‹</Link>
        <h1 className="font-heading text-[1.4rem] font-bold text-ink">CSV Import</h1>
      </div>

      {/* Step indicators */}
      <div className="flex gap-1.5 items-center">
        {(['upload', 'preview', 'done'] as Step[]).map((s, i) => {
          const done = (step === 'preview' && s === 'upload') || step === 'done'
          const active = step === s
          return (
            <div key={s} className="flex items-center gap-1.5">
              <div className={`w-6 h-6 rounded-full flex items-center justify-center text-[0.72rem] font-bold
                ${active ? 'bg-accent text-white' : done ? 'bg-[#d1fae5] text-[#065f46]' : 'bg-edge text-muted'}`}>
                {done ? '✓' : i + 1}
              </div>
              <span className={`text-[0.78rem] ${active ? 'text-ink font-semibold' : 'text-muted'}`}>
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </span>
              {i < 2 && <span className="text-edge text-[0.8rem]">›</span>}
            </div>
          )
        })}
      </div>

      {/* Step 1: Upload */}
      {step === 'upload' && (
        <section className="card p-5 flex flex-col gap-4">
          <p className="text-[0.875rem] text-muted">
            Export your collection from BGG as a CSV and upload it here.
          </p>
          <input
            ref={fileRef}
            type="file"
            accept=".csv"
            onChange={e => { setFile(e.target.files?.[0] ?? null); setPreviewError(null) }}
            className="text-[0.875rem] text-ink"
          />
          {previewError && <div className="alert-error">{previewError}</div>}
          <button
            onClick={handlePreview}
            disabled={!file || previewing}
            className="pressable btn btn-primary self-start disabled:opacity-50"
          >
            {previewing ? 'Loading preview…' : 'Preview'}
          </button>
        </section>
      )}

      {/* Step 2: Preview */}
      {step === 'preview' && preview && (
        <div className="flex flex-col gap-4">
          <p className="text-[0.82rem] text-muted">
            {preview.total_rows} games in CSV
            {preview.total_rows > preview.preview_limit && ` (showing first ${preview.preview_limit})`}
            {' · '}{newRows.length} new · {preview.rows.length - newRows.length} already owned
          </p>

          <section className="card p-5 overflow-x-auto">
            <table className="w-full border-collapse text-[0.83rem]">
              <thead>
                <tr className="border-b border-edge">
                  <th className="text-left px-2 py-1.5 text-muted font-semibold">Game</th>
                  <th className="text-right px-2 py-1.5 text-muted font-semibold">BGG ID</th>
                  <th className="text-center px-2 py-1.5 text-muted font-semibold">Status</th>
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((row: CSVPreviewRow) => (
                  <tr key={row.bgg_id} className={`border-b border-edge ${row.already_owned ? 'opacity-55' : ''}`}>
                    <td className="px-2 py-1.5 text-ink">{row.name}</td>
                    <td className="px-2 py-1.5 text-muted text-right">{row.bgg_id}</td>
                    <td className="px-2 py-1.5 text-center">
                      {row.already_owned
                        ? <span className="text-muted text-[0.75rem]">owned</span>
                        : <span className="text-[#059669] text-[0.75rem] font-semibold">new</span>
                      }
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>

          {importError && <div className="alert-error">{importError}</div>}

          <div className="flex gap-3 flex-wrap">
            <button
              onClick={handleImport}
              disabled={importing || newRows.length === 0}
              className="pressable btn btn-primary disabled:opacity-50"
            >
              {importing ? 'Importing…' : `Import ${newRows.length} game${newRows.length !== 1 ? 's' : ''}`}
            </button>
            <button onClick={reset} className="pressable btn btn-secondary">Cancel</button>
          </div>
        </div>
      )}

      {/* Step 3: Done */}
      {step === 'done' && result && (
        <section className="card p-5 flex flex-col gap-4">
          <div className="text-center py-4 flex flex-col items-center gap-4">
            <div className="text-[2.5rem]">✓</div>
            <div className="font-heading text-[1.2rem] text-ink">Import complete</div>
            <div className="flex justify-center gap-10">
              {([
                { label: 'Imported', value: result.imported, color: '#059669' },
                { label: 'Failed',   value: result.failed,   color: '#b91c1c' },
              ] as const).map(s => (
                <div key={s.label} className="text-center">
                  <div className="font-heading text-[2rem] font-bold" style={{ color: s.color }}>{s.value}</div>
                  <div className="text-[0.72rem] text-muted uppercase tracking-wider">{s.label}</div>
                </div>
              ))}
            </div>
          </div>
          <div className="flex gap-3 flex-wrap justify-center">
            <Link to="/" className="pressable btn btn-primary no-underline">View Collection</Link>
            <button onClick={reset} className="pressable btn btn-secondary">Import another</button>
          </div>
        </section>
      )}
    </div>
  )
}
