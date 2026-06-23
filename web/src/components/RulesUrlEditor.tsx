import { useState } from 'react'
import { useRulesUrl } from '../hooks/useRulesUrl'

const DRIVE_RE = /^https:\/\/(drive|docs)\.google\.com\//

interface Props {
  gameId: number
  initial: string
}

export default function RulesUrlEditor({ gameId, initial }: Props) {
  const [url, setUrl] = useState(initial)
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(initial)
  const [error, setError] = useState('')
  const { updateRulesUrl } = useRulesUrl(gameId)

  async function handleSave() {
    const trimmed = draft.trim()
    if (trimmed && !DRIVE_RE.test(trimmed)) { setError('Must be a Google Drive or Docs URL'); return }
    setError('')
    try {
      await updateRulesUrl.mutateAsync(trimmed)
      setUrl(trimmed)
      setEditing(false)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  function handleCancel() { setDraft(url); setError(''); setEditing(false) }

  if (editing) {
    return (
      <div className="card p-4">
        <div className="field-label mb-1">Rulebook URL</div>
        <input type="url" value={draft} onChange={e => { setDraft(e.target.value); setError('') }}
          placeholder="https://drive.google.com/…" autoFocus className="form-input" />
        {error && <div className="alert-error mt-1">{error}</div>}
        <div className="flex gap-2 mt-2">
          <button onClick={handleSave} disabled={updateRulesUrl.isPending}
            className="btn btn-primary pressable text-[0.85rem] px-3.5 py-1.5">
            {updateRulesUrl.isPending ? 'Saving…' : 'Save'}
          </button>
          <button onClick={handleCancel} className="btn btn-secondary pressable text-[0.85rem] px-3.5 py-1.5">
            Cancel
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="flex items-center gap-2">
      {url ? (
        <a href={url} target="_blank" rel="noopener noreferrer"
          className="pressable card flex items-center gap-3 p-4 flex-1 text-ink">
          <span className="text-xl">📖</span>
          <span className="flex-1 text-[0.9rem] font-semibold">Rulebook</span>
          <span className="text-muted">↗</span>
        </a>
      ) : (
        <div className="card flex items-center gap-3 p-4 flex-1 text-muted">
          <span className="text-xl">📖</span>
          <span className="flex-1 text-[0.9rem]">No rulebook link</span>
        </div>
      )}
      <button onClick={() => { setDraft(url); setEditing(true) }} title="Edit rulebook URL"
        className="pressable card p-4 text-muted cursor-pointer flex items-center justify-center shrink-0">
        ✏️
      </button>
    </div>
  )
}
