import { useState, useRef } from 'react'
import { api, ApiError, type Collection } from '../lib/api'
import type { Game } from '../types/game'
import GameListItem from '../components/GameListItem'
import { useCollections } from '../hooks/useCollections'

const PALETTE = [
  { bg: '#dbeafe', text: '#1d4ed8', border: '#93c5fd' },
  { bg: '#fee2e2', text: '#b91c1c', border: '#fca5a5' },
  { bg: '#ccfbf1', text: '#0f766e', border: '#5eead4' },
  { bg: '#fef9c3', text: '#a16207', border: '#fde047' },
  { bg: '#ede9fe', text: '#6d28d9', border: '#c4b5fd' },
  { bg: '#d1fae5', text: '#065f46', border: '#6ee7b7' },
  { bg: '#e0e7ff', text: '#3730a3', border: '#a5b4fc' },
  { bg: '#f3e8ff', text: '#7e22ce', border: '#d8b4fe' },
  { bg: '#ffedd5', text: '#9a3412', border: '#fdba74' },
  { bg: '#fef3c7', text: '#92400e', border: '#fcd34d' },
  { bg: '#fce7f3', text: '#9d174d', border: '#f9a8d4' },
  { bg: '#ecfccb', text: '#3f6212', border: '#bef264' },
]

function pillColor(idx: number) {
  return PALETTE[idx % PALETTE.length]
}

export default function VibesPage() {
  const { collections, createCollection, updateCollection, deleteCollection, loading: loadingCollections } = useCollections()
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [games, setGames] = useState<Game[]>([])
  const [discoverTotal, setDiscoverTotal] = useState(0)
  const [loadingGames, setLoadingGames] = useState(false)

  const [managing, setManaging] = useState(false)
  const [newName, setNewName] = useState('')
  const [creating, setCreating] = useState(false)
  const [createError, setCreateError] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [editingName, setEditingName] = useState('')
  const [renameSaving, setRenameSaving] = useState(false)
  const [deletingId, setDeletingId] = useState<number | null>(null)
  const newNameRef = useRef<HTMLInputElement>(null)

  function toggleManage() {
    setManaging(m => !m)
    setSelectedId(null)
    setGames([])
    setNewName('')
    setCreateError(null)
    setEditingId(null)
    setDeletingId(null)
  }

  async function handleCreate() {
    const name = newName.trim()
    if (!name) return
    setCreating(true)
    setCreateError(null)
    try {
      await createCollection(name)
      setNewName('')
    } catch (e) {
      setCreateError(e instanceof ApiError ? e.message : 'Failed to create')
    } finally {
      setCreating(false)
    }
  }

  function startEdit(col: Collection) {
    setEditingId(col.id)
    setEditingName(col.name)
    setDeletingId(null)
  }

  async function saveRename(id: number) {
    const name = editingName.trim()
    if (!name) return
    setRenameSaving(true)
    try {
      await updateCollection(id, name)
      setEditingId(null)
    } catch {
      // keep editing open on failure
    } finally {
      setRenameSaving(false)
    }
  }

  async function handleDelete(id: number) {
    try {
      await deleteCollection(id)
      setDeletingId(null)
      if (selectedId === id) { setSelectedId(null); setGames([]) }
    } catch {
      setDeletingId(null)
    }
  }

  function selectCollection(id: number) {
    if (id === selectedId) {
      setSelectedId(null)
      setGames([])
      return
    }
    setSelectedId(id)
    setLoadingGames(true)
    api.discover({ collection_id: id })
      .then(res => {
        setGames(res.data)
        setDiscoverTotal(res.total)
      })
      .catch(() => {
        setGames([])
        setDiscoverTotal(0)
      })
      .finally(() => setLoadingGames(false))
  }

  const selectedName = collections.find(c => c.id === selectedId)?.name ?? ''

  return (
    <div className="flex flex-col gap-4">
      {/* Page header */}
      <div className="pt-1 flex items-start justify-between">
        <div>
          <h1 className="font-heading text-[1.6rem] font-bold text-ink mb-0.5">Browse by Vibe</h1>
          <p className="text-[0.82rem] text-muted">Pick a mood and find your next game</p>
        </div>
        <button
          onClick={toggleManage}
          className={`pressable mt-1 px-3 py-1.5 rounded-lg text-[0.78rem] font-semibold font-sans border border-edge cursor-pointer ${managing ? 'bg-accent text-white' : 'bg-parchment text-muted'}`}
        >
          {managing ? 'Done' : 'Edit'}
        </button>
      </div>

      {/* Collection pills */}
      {loadingCollections ? (
        <div className="flex flex-wrap gap-2">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="h-9 bg-edge rounded-full" style={{ width: `${70 + (i * 17) % 50}px` }} />
          ))}
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <div className="flex flex-wrap gap-2">
            {collections.map((col, idx) => {
              const c = pillColor(idx)
              const isSelected = col.id === selectedId
              const isEditing = editingId === col.id
              const isConfirmingDelete = deletingId === col.id

              if (managing && isEditing) {
                return (
                  <div key={col.id} className="flex items-center gap-1.5">
                    <input
                      autoFocus
                      value={editingName}
                      onChange={e => setEditingName(e.target.value)}
                      onKeyDown={e => {
                        if (e.key === 'Enter') saveRename(col.id)
                        if (e.key === 'Escape') setEditingId(null)
                      }}
                      className="px-3 py-1.5 rounded-full text-[0.875rem] font-semibold font-sans focus:outline-none"
                      style={{
                        border: `1.5px solid ${c.text}`,
                        color: c.text,
                        background: c.bg,
                        minWidth: '7rem',
                      }}
                    />
                    <button
                      onClick={() => saveRename(col.id)}
                      disabled={renameSaving}
                      className="pressable rounded-full px-2.5 py-1 text-[0.75rem] font-bold text-white border-none cursor-pointer"
                      style={{ background: c.text }}
                    >
                      {renameSaving ? '…' : '✓'}
                    </button>
                    <button
                      onClick={() => setEditingId(null)}
                      className="pressable rounded-full px-2.5 py-1 text-[0.75rem] font-bold bg-edge text-muted border-none cursor-pointer"
                    >
                      ✕
                    </button>
                  </div>
                )
              }

              if (managing && isConfirmingDelete) {
                return (
                  <div key={col.id} className="flex items-center gap-1.5">
                    <span className="text-[0.82rem] text-[#b91c1c] font-medium">Delete "{col.name}"?</span>
                    <button
                      onClick={() => handleDelete(col.id)}
                      className="pressable rounded-full px-3 py-1 text-[0.75rem] font-bold text-white bg-[#b91c1c] border-none cursor-pointer"
                    >
                      Delete
                    </button>
                    <button
                      onClick={() => setDeletingId(null)}
                      className="pressable rounded-full px-2.5 py-1 text-[0.75rem] font-bold bg-edge text-muted border-none cursor-pointer"
                    >
                      Cancel
                    </button>
                  </div>
                )
              }

              return (
                <div key={col.id} className="inline-flex items-center gap-1">
                  <button
                    onClick={() => managing ? startEdit(col) : selectCollection(col.id)}
                    className="pressable rounded-full px-4 py-1.5 text-[0.875rem] font-semibold font-sans cursor-pointer inline-flex items-center gap-1.5"
                    style={{
                      background: isSelected ? c.text : c.bg,
                      color: isSelected ? 'white' : c.text,
                      border: `1.5px solid ${isSelected ? c.text : c.border}`,
                      boxShadow: isSelected ? `0 2px 8px ${c.border}` : 'none',
                    }}
                  >
                    {managing && <span className="text-[0.75rem] opacity-70">✎</span>}
                    {!managing && isSelected && <span className="text-[0.75rem]">✓</span>}
                    {col.name}
                    {!managing && col.gameCount > 0 && (
                      <span
                        className="text-[0.7rem] rounded-full px-[0.45rem] py-[0.05rem] font-bold"
                        style={{
                          background: isSelected ? 'rgba(255,255,255,0.25)' : c.border,
                          color: isSelected ? 'white' : c.text,
                        }}
                      >
                        {col.gameCount}
                      </span>
                    )}
                  </button>
                  {managing && (
                    <button
                      onClick={() => setDeletingId(col.id)}
                      className="pressable w-[1.4rem] h-[1.4rem] rounded-full flex items-center justify-center text-[0.7rem] font-bold bg-[#fee2e2] text-[#b91c1c] border-none cursor-pointer shrink-0"
                    >
                      ✕
                    </button>
                  )}
                </div>
              )
            })}
          </div>

          {/* New vibe form */}
          {managing && (
            <div className="flex items-center gap-2 flex-wrap">
              <input
                ref={newNameRef}
                value={newName}
                onChange={e => { setNewName(e.target.value); setCreateError(null) }}
                onKeyDown={e => { if (e.key === 'Enter') handleCreate() }}
                placeholder="New vibe name…"
                className="px-3 py-1.5 rounded-full text-[0.875rem] font-sans bg-parchment text-ink border border-edge focus:outline-none focus:border-accent min-w-[10rem]"
              />
              <button
                onClick={handleCreate}
                disabled={creating || !newName.trim()}
                className="pressable rounded-full px-4 py-1.5 text-[0.875rem] font-semibold font-sans bg-accent text-white border-none cursor-pointer disabled:opacity-50"
              >
                {creating ? '…' : '+ Add'}
              </button>
              {createError && (
                <span className="text-[0.78rem] text-[#b91c1c]">{createError}</span>
              )}
            </div>
          )}
        </div>
      )}

      {/* Results */}
      {selectedId !== null && (
        <div className="flex flex-col gap-2">
          {loadingGames ? (
            <>
              <div className="h-3 w-2/5 bg-edge rounded" />
              {Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="h-[72px] bg-edge rounded-[0.875rem]" />
              ))}
            </>
          ) : (
            <>
              <div className="text-[0.8rem] text-muted">
                {discoverTotal} {discoverTotal === 1 ? 'game' : 'games'} with "{selectedName}" vibe
              </div>
              {games.length === 0 ? (
                <div className="text-center py-12 text-muted">
                  <div className="text-[2rem] mb-2">🎲</div>
                  <div className="font-heading text-base">No games found</div>
                </div>
              ) : (
                games.map(g => <GameListItem key={g.id} game={g} />)
              )}
            </>
          )}
        </div>
      )}

      {/* Empty state */}
      {selectedId === null && !loadingCollections && (
        <div className="text-center py-12 text-muted">
          <div className="text-[2.5rem] mb-3">✦</div>
          <div className="font-heading text-[1.05rem] mb-1">Choose a vibe above</div>
          <div className="text-[0.82rem]">See which games match your mood</div>
        </div>
      )}
    </div>
  )
}
