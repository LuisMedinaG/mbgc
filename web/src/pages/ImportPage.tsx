import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ApiError, type BGGPreviewResult, type SyncResult } from '../lib/api'
import { useProfile } from '../hooks/useProfile'
import { useImport } from '../hooks/useImport'

export default function ImportPage() {
  const { profile } = useProfile()
  const { previewBGG, syncBGG, createListWithGames } = useImport()
  const bggUsername = profile?.bgg_username ?? ''

  const [error, setError] = useState<string | null>(null)
  const [fullRefresh, setFullRefresh] = useState(false)
  const [preview, setPreview] = useState<BGGPreviewResult | null>(null)
  const [result, setResult] = useState<SyncResult | null>(null)
  const [listName, setListName] = useState('')
  const [listDone, setListDone] = useState<string | null>(null)

  async function handlePreview() {
    setError(null); setResult(null); setListDone(null)
    try {
      setPreview(await previewBGG.mutateAsync())
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Preview failed')
    }
  }

  async function handleSync() {
    setError(null)
    try {
      setResult(await syncBGG.mutateAsync(fullRefresh))
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Sync failed')
    }
  }

  async function handleCreateList() {
    if (!listName.trim() || !result?.imported_ids?.length) return
    try {
      await createListWithGames.mutateAsync({ name: listName.trim(), gameIds: result.imported_ids })
      setListDone(listName.trim())
      setListName('')
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not create list')
    }
  }

  function restart() {
    setPreview(null); setResult(null); setError(null); setListDone(null)
  }

  const willAdd = preview ? (fullRefresh ? preview.total : preview.new) : 0
  const importedIds = result?.imported_ids ?? []

  return (
    <div className="flex flex-col gap-5 pt-1">
      <div>
        <h1 className="font-heading text-[1.6rem] font-bold text-ink mb-0.5">Import</h1>
        <p className="text-[0.82rem] text-muted">Sync from BoardGameGeek or import a CSV</p>
      </div>

      {/* BGG Sync */}
      <section className="card p-5 flex flex-col gap-4">
        <div className="text-[0.78rem] font-semibold text-muted uppercase tracking-wider">BoardGameGeek Sync</div>

        {!bggUsername ? (
          <p className="text-[0.875rem] text-muted">
            Set your BGG username in{' '}
            <Link to="/profile" className="text-accent">Profile</Link>{' '}
            before syncing.
          </p>
        ) : (
          <p className="text-[0.875rem] text-ink">
            Syncing as <strong>{bggUsername}</strong>
          </p>
        )}

        <label className="flex items-center gap-2 text-[0.875rem] cursor-pointer">
          <input
            type="checkbox"
            checked={fullRefresh}
            onChange={e => setFullRefresh(e.target.checked)}
            className="w-4 h-4"
          />
          <span className="text-ink">Full refresh</span>
          <span className="text-[0.78rem] text-muted">(re-fetch all games)</span>
        </label>

        {error && <div className="alert-error">{error}</div>}

        {/* Preview: how many will be added */}
        {preview && !result && (
          <div className="bg-edge/40 rounded-lg px-4 py-3 text-[0.875rem] text-ink">
            <strong>{willAdd}</strong> {willAdd === 1 ? 'game' : 'games'} will be added
            <span className="text-muted"> · {preview.owned} already owned · {preview.total} in collection</span>
          </div>
        )}

        {/* Result: colored status bullets */}
        {result && (
          <div className="bg-edge/30 rounded-lg px-4 py-3 flex gap-6">
            {([
              { label: 'Imported', value: result.imported, color: '#059669' },
              { label: 'Skipped',  value: result.skipped,  color: '#d97706' },
              { label: 'Failed',   value: failedCount(result), color: '#dc2626' },
            ] as const).map(s => (
              <div key={s.label} className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full" style={{ background: s.color }} />
                <div>
                  <div className="font-heading text-[1.25rem] font-bold" style={{ color: s.color }}>{s.value}</div>
                  <div className="text-[0.72rem] text-muted uppercase tracking-wider">{s.label}</div>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Create a list from the imported games */}
        {result && importedIds.length > 0 && (
          listDone ? (
            <p className="text-[0.875rem] text-[#059669]">
              Added {importedIds.length} {importedIds.length === 1 ? 'game' : 'games'} to <strong>{listDone}</strong>.
            </p>
          ) : (
            <div className="flex flex-col gap-2">
              <label className="text-[0.78rem] font-semibold text-muted">Add these {importedIds.length} games to a new list</label>
              <div className="flex gap-2 flex-wrap">
                <input
                  value={listName}
                  onChange={e => setListName(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && handleCreateList()}
                  placeholder="List name"
                  className="form-input flex-1 min-w-[12rem]"
                />
                <button
                  onClick={handleCreateList}
                  disabled={!listName.trim() || createListWithGames.isPending}
                  className="pressable btn btn-secondary disabled:opacity-50"
                >
                  {createListWithGames.isPending ? 'Creating…' : 'Create list'}
                </button>
              </div>
            </div>
          )
        )}

        {/* Actions */}
        <div className="flex gap-3 flex-wrap">
          {!preview && (
            <button
              onClick={handlePreview}
              disabled={previewBGG.isPending || !bggUsername}
              className="pressable btn btn-primary self-start disabled:opacity-50"
            >
              {previewBGG.isPending ? 'Checking…' : 'Preview'}
            </button>
          )}
          {preview && !result && (
            <>
              <button
                onClick={handleSync}
                disabled={syncBGG.isPending || willAdd === 0}
                className="pressable btn btn-primary disabled:opacity-50"
              >
                {syncBGG.isPending ? 'Syncing…' : `Import ${willAdd} game${willAdd !== 1 ? 's' : ''}`}
              </button>
              <button onClick={restart} className="pressable btn btn-secondary">Cancel</button>
            </>
          )}
          {result && (
            <button onClick={restart} className="pressable btn btn-secondary">Sync again</button>
          )}
        </div>
      </section>

      {/* CSV Import */}
      <section className="card p-5 flex flex-col gap-4">
        <div className="text-[0.78rem] font-semibold text-muted uppercase tracking-wider">CSV Import</div>
        <p className="text-[0.875rem] text-muted">Import games from a BGG-exported CSV file.</p>
        <Link to="/import/csv" className="pressable btn btn-secondary self-start">
          Import from CSV →
        </Link>
      </section>
    </div>
  )
}

// Backend sends `failed` as a list of BGG IDs (omitempty), the type narrows it to a count.
function failedCount(r: SyncResult): number {
  const f = r.failed as unknown
  return Array.isArray(f) ? f.length : Number(f) || 0
}
