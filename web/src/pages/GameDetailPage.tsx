import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useGame } from '../hooks/useGame'
import { playersStr, weightClass, weightLabel, imgFallback } from '../utils/gameFormatters'
import TagList from '../components/TagList'
import PlayerAidManager from '../components/PlayerAidManager'
import RulesUrlEditor from '../components/RulesUrlEditor'

const LANG_DEP = ['', 'No language', 'Some text', 'Moderate', 'Extensive', 'Unplayable']

export default function GameDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { game, allCollections, loading, error, saveVibes, deleteGame } = useGame(Number(id ?? 0))

  const [descExpanded, setDescExpanded] = useState(false)
  const [selectedVibeIds, setSelectedVibeIds] = useState<Set<number>>(new Set())
  const [editingVibes, setEditingVibes] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)

  // ref: game-detail.VIBE_ASSIGN.2 — calls POST /api/v1/games/{id}/collections with full ID set
  // ref: game-detail.VIBE_ASSIGN.3 — cache invalidation keeps UI current without page reload
  async function handleSaveVibes() {
    await saveVibes.mutateAsync([...selectedVibeIds])
    setEditingVibes(false)
  }

  function toggleVibe(vid: number) {
    setSelectedVibeIds(prev => {
      const next = new Set(prev)
      if (next.has(vid)) next.delete(vid)
      else next.add(vid)
      return next
    })
  }

  // ref: game-detail.DELETE.1 — requires explicit confirmation before deleting
  async function handleDelete() {
    await deleteGame.mutateAsync()
  }

  if (loading) {
    return (
      <div className="pb-2">
        <div className="-mx-4 h-[240px] bg-edge" />
        <div className="flex flex-col gap-3 mt-4">
          {[1, 2, 3].map(i => (
            <div key={i} className="h-20 bg-edge rounded-[0.875rem]" />
          ))}
        </div>
      </div>
    )
  }

  if (error || !game) {
    return (
      <div className="text-center py-16 text-muted">
        <div className="text-[2.5rem] mb-3">🎲</div>
        <div className="font-heading text-[1.1rem] mb-3">{error || 'Game not found.'}</div>
        <button onClick={() => navigate(-1)} className="btn btn-secondary pressable">‹ Back</button>
      </div>
    )
  }

  const bggUrl = `https://boardgamegeek.com/boardgame/${game.bggId}`

  return (
    <div className="pb-2">
      {/* ref: game-detail.DETAIL_VIEW.2 — full metadata render (hero image, stats, tags, etc.) */}
      <div className="-mx-4 h-[240px] relative overflow-hidden bg-edge">
        <img
          src={game.image || game.thumbnail}
          alt={game.name}
          onError={e => { e.currentTarget.src = imgFallback(game.name) }}
          className="w-full h-full object-cover block"
        />
        <div className="absolute inset-0 bg-gradient-to-b from-transparent to-black/60" />
        <div className="absolute bottom-4 left-4 right-4">
          <h1 className="text-[1.6rem] font-bold leading-[1.15] text-white mb-1.5" style={{ textShadow: '0 1px 4px rgba(0,0,0,0.5)' }}>
            {game.name}
          </h1>
          <div className="flex items-center flex-wrap gap-1.5 text-[0.8rem] text-white/85">
            {game.yearPublished > 0 && <span>{game.yearPublished}</span>}
            {game.rating > 0 && (
              <span className="bg-rating text-white rounded px-[0.45rem] py-[0.1rem] text-[0.75rem] font-bold">
                ★ {game.rating.toFixed(1)}
              </span>
            )}
            <span className={weightClass(game.weight)}>{weightLabel(game.weight)}</span>
            {game.languageDependence > 0 && (
              <span className="bg-black/40 rounded px-[0.45rem] py-[0.1rem] text-[0.75rem]">
                🗣 {LANG_DEP[game.languageDependence]}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Stats row */}
      <div className="card grid grid-cols-3 my-4 overflow-hidden">
        {[
          { label: 'Players',    value: playersStr(game), sub: 'count' },
          { label: 'Playtime',   value: `${game.playTime}`, sub: 'minutes' },
          { label: 'Complexity', value: game.weight > 0 ? game.weight.toFixed(1) : '—', sub: '/ 5.0' },
        ].map((stat, i) => (
          <div
            key={stat.label}
            className={`flex flex-col items-center py-4 px-2 ${i < 2 ? 'border-r border-edge' : ''}`}
          >
            <div className="font-heading text-[1.5rem] font-bold text-ink leading-none">{stat.value}</div>
            <div className="text-[0.62rem] font-bold uppercase tracking-wider text-accent mt-1">{stat.label}</div>
            <div className="text-[0.62rem] text-muted opacity-80">{stat.sub}</div>
          </div>
        ))}
      </div>

      {/* Description */}
      {game.description && (
        <div className="card p-4 mb-3">
          <h2 className="text-[0.85rem] font-bold text-muted uppercase tracking-wider mb-3">About</h2>
          <p className={`text-[0.875rem] leading-relaxed text-ink ${descExpanded ? '' : 'line-clamp-3'}`}>
            {game.description}
          </p>
          {game.description.length > 200 && (
            <button
              onClick={() => setDescExpanded(p => !p)}
              className="pressable bg-transparent border-none pt-1.5 text-[0.82rem] text-accent font-semibold cursor-pointer font-sans"
            >
              {descExpanded ? 'Show less ↑' : 'Read more ↓'}
            </button>
          )}
        </div>
      )}

      {/* Tags */}
      {(game.types.length > 0 || game.categories.length > 0 || game.mechanics.length > 0) && (
        <div className="card p-4 mb-3 flex flex-col gap-3">
          <TagList label="Type" tags={game.types} variant="type" />
          <TagList label="Categories" tags={game.categories} variant="category" />
          <TagList label="Mechanics" tags={game.mechanics} variant="mechanic" />
        </div>
      )}

      {/* Player aids */}
      <PlayerAidManager gameId={game.id} initial={game.playerAids} />

      {/* Vibes */}
      <div className="card p-4 mb-3">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-[0.85rem] font-bold text-muted uppercase tracking-wider">Vibes</h2>
          {!editingVibes && (
            <button
              onClick={() => { setSelectedVibeIds(new Set(game?.vibeCollectionIds ?? [])); setEditingVibes(true) }}
              className="pressable bg-transparent border-none text-[0.82rem] text-accent font-semibold cursor-pointer font-sans py-0"
            >
              Edit
            </button>
          )}
        </div>

        {editingVibes ? (
          <>
            <div className="flex flex-col gap-1.5 mb-3">
              {allCollections.map(c => (
                <label key={c.id} className="flex items-center gap-2 cursor-pointer text-[0.9rem] text-ink">
                  <input
                    type="checkbox"
                    checked={selectedVibeIds.has(c.id)}
                    onChange={() => toggleVibe(c.id)}
                    className="w-4 h-4 cursor-pointer accent-accent"
                  />
                  {c.name}
                </label>
              ))}
              {allCollections.length === 0 && (
                <div className="text-[0.85rem] text-muted">No collections yet.</div>
              )}
            </div>
            <div className="flex gap-2">
              <button
                onClick={handleSaveVibes}
                disabled={saveVibes.isPending}
                className="btn btn-primary pressable text-[0.85rem] px-3.5 py-1.5 disabled:opacity-50"
              >
                {saveVibes.isPending ? 'Saving…' : 'Save'}
              </button>
              <button
                onClick={() => setEditingVibes(false)}
                className="btn btn-secondary pressable text-[0.85rem] px-3.5 py-1.5"
              >
                Cancel
              </button>
            </div>
          </>
        ) : (
          game.vibes.length > 0 ? (
            <div className="flex flex-wrap gap-1.5">
              {game.vibes.map(v => (
                <span key={v} className="vibe-pill">{v}</span>
              ))}
            </div>
          ) : (
            <div className="text-[0.85rem] text-muted">No vibes assigned.</div>
          )
        )}
      </div>

      {/* External links */}
      <div className="flex flex-col gap-2 mb-3">
        <RulesUrlEditor gameId={game.id} initial={game.rulesUrl} />
        <a
          href={bggUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="pressable card flex items-center gap-3 p-4 text-ink"
        >
          <span className="text-xl">🎲</span>
          <span className="flex-1 text-[0.9rem] font-semibold">View on BoardGameGeek</span>
          <span className="text-muted text-base">↗</span>
        </a>
      </div>

      {/* Delete */}
      <div className="border-t border-edge pt-4 mt-1">
        {confirmDelete ? (
          <div className="flex items-center gap-3 flex-wrap">
            <span className="text-[0.875rem] text-ink font-semibold">Delete "{game.name}"?</span>
            <button
              onClick={handleDelete}
              disabled={deleteGame.isPending}
              className="pressable px-3.5 py-1.5 text-[0.85rem] font-semibold rounded-lg bg-[#dc2626] text-white border-none cursor-pointer disabled:opacity-60 font-sans"
            >
              {deleteGame.isPending ? 'Deleting…' : 'Yes, delete'}
            </button>
            <button
              onClick={() => setConfirmDelete(false)}
              className="btn btn-secondary pressable text-[0.85rem] px-3.5 py-1.5"
            >
              Cancel
            </button>
          </div>
        ) : (
          <button
            onClick={() => setConfirmDelete(true)}
            className="pressable bg-transparent border-none p-0 text-[0.85rem] text-[#dc2626] cursor-pointer font-semibold font-sans"
          >
            Delete game
          </button>
        )}
      </div>
    </div>
  )
}
