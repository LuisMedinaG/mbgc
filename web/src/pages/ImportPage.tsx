import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { api, ApiError, type SyncResult } from '../lib/api'

export default function ImportPage() {
  const [bggUsername, setBggUsername] = useState('')
  const [syncing, setSyncing] = useState(false)
  const [syncResult, setSyncResult] = useState<SyncResult | null>(null)
  const [syncError, setSyncError] = useState<string | null>(null)
  const [fullRefresh, setFullRefresh] = useState(false)

  useEffect(() => {
    api.getProfile().then(p => setBggUsername(p.bgg_username ?? '')).catch(() => {})
  }, [])

  async function handleSync() {
    setSyncing(true)
    setSyncResult(null)
    setSyncError(null)
    try {
      const r = await api.syncBGG(fullRefresh)
      setSyncResult(r)
    } catch (e) {
      setSyncError(e instanceof ApiError ? e.message : 'Sync failed')
    } finally {
      setSyncing(false)
    }
  }

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

        {syncError && <div className="alert-error">{syncError}</div>}

        {syncResult && (
          <div className="bg-[#d1fae5] rounded-lg px-4 py-3 flex gap-6">
            {([
              { label: 'Added',   value: syncResult.added },
              { label: 'Updated', value: syncResult.updated },
              { label: 'Total',   value: syncResult.total },
            ] as const).map(s => (
              <div key={s.label}>
                <div className="font-heading text-[1.25rem] font-bold text-[#065f46]">{s.value}</div>
                <div className="text-[0.72rem] text-[#065f46] uppercase tracking-wider">{s.label}</div>
              </div>
            ))}
          </div>
        )}

        <button
          onClick={handleSync}
          disabled={syncing || !bggUsername}
          className="pressable btn btn-primary self-start disabled:opacity-50"
        >
          {syncing ? 'Syncing…' : 'Sync from BGG'}
        </button>
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
