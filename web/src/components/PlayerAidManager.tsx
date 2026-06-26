import { useState, useEffect } from 'react'
import { type PlayerAid } from '../lib/api'
import { usePlayerAids } from '../hooks/usePlayerAids'

interface Props {
  gameId: number
  initial: PlayerAid[]
}

export default function PlayerAidManager({ gameId, initial }: Props) {
  const { aids, uploadPlayerAid, deletePlayerAid } = usePlayerAids(gameId, initial)
  const [lightbox, setLightbox] = useState<number | null>(null)
  const [uploadErr, setUploadErr] = useState('')
  const [labelInput, setLabelInput] = useState('')

  useEffect(() => {
    if (lightbox === null) return
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setLightbox(null)
      else if (e.key === 'ArrowLeft') setLightbox(p => (p !== null && p > 0 ? p - 1 : p))
      else if (e.key === 'ArrowRight') setLightbox(p => (p !== null && p < aids.length - 1 ? p + 1 : p))
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [lightbox, aids.length])

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadErr('')
    try {
      const label = labelInput.trim() || file.name.replace(/\.[^.]+$/, '')
      await uploadPlayerAid.mutateAsync({ file, label })
      setLabelInput('')
      e.target.value = ''
    } catch (err) {
      setUploadErr(err instanceof Error ? err.message : 'Upload failed')
    }
  }

  async function handleDelete(aid: PlayerAid) {
    if (!confirm(`Delete "${aid.label}"?`)) return
    try {
      await deletePlayerAid.mutateAsync(aid.id)
      setLightbox(null)
    } catch { /* ignore */ }
  }

  const cur = lightbox !== null ? aids[lightbox] : null

  return (
    <>
      <div className="card p-4 mb-3">
        <h2 className="section-label mb-3">Player Aids</h2>

        {aids.length > 0 && (
          <div className="flex gap-3 overflow-x-auto pb-2 mb-3">
            {aids.map((aid, i) => (
              <div key={aid.id} className="shrink-0 relative">
                <button onClick={() => setLightbox(i)}
                  className="pressable bg-transparent border-none p-0 cursor-pointer block">
                  <img src={`/uploads/${aid.filename}`} alt={aid.label}
                    className="w-[120px] h-[90px] object-cover rounded-lg border border-edge block" />
                  <div className="text-[0.7rem] text-muted mt-1 text-center w-[120px] truncate">{aid.label}</div>
                </button>
                <button onClick={() => handleDelete(aid)} title="Delete player aid"
                  className="pressable absolute top-1 right-1 bg-black/60 border-none rounded-full w-5 h-5 flex items-center justify-center cursor-pointer text-white text-[0.65rem]">
                  ✕
                </button>
              </div>
            ))}
          </div>
        )}

        <div className="flex gap-2 items-center flex-wrap">
          <input type="text" placeholder="Label (optional)" value={labelInput}
            onChange={e => setLabelInput(e.target.value)}
            className="flex-1 min-w-[120px] px-3 py-[0.45rem] text-[0.85rem] border border-edge rounded-lg bg-parchment text-ink font-sans focus:outline-none focus:border-accent" />
          <label className={`pressable inline-flex items-center gap-1 px-3.5 py-[0.45rem] text-[0.85rem] font-semibold rounded-lg border-none font-sans cursor-pointer ${uploadPlayerAid.isPending ? 'bg-edge text-muted cursor-not-allowed' : 'bg-accent text-white'}`}>
            {uploadPlayerAid.isPending ? 'Uploading…' : '+ Upload'}
            <input type="file" accept="image/png,image/jpeg,image/gif,image/webp"
              onChange={handleUpload} disabled={uploadPlayerAid.isPending} hidden />
          </label>
        </div>

        {uploadErr && <div className="text-[0.8rem] text-[#dc2626] mt-1.5">{uploadErr}</div>}
      </div>

      {cur && (
        <div onClick={() => setLightbox(null)}
          className="fixed inset-0 bg-black/85 z-[1000] flex items-center justify-center">
          <img src={`/uploads/${cur.filename}`} alt={cur.label}
            onClick={e => e.stopPropagation()}
            className="max-w-[90vw] max-h-[85vh] object-contain rounded-lg" />

          {lightbox! > 0 && (
            <button onClick={e => { e.stopPropagation(); setLightbox(p => p! - 1) }}
              className="pressable absolute left-4 top-1/2 -translate-y-1/2 bg-white/15 border-none rounded-full w-10 h-10 text-white text-2xl cursor-pointer flex items-center justify-center">
              ‹
            </button>
          )}
          {lightbox! < aids.length - 1 && (
            <button onClick={e => { e.stopPropagation(); setLightbox(p => p! + 1) }}
              className="pressable absolute right-4 top-1/2 -translate-y-1/2 bg-white/15 border-none rounded-full w-10 h-10 text-white text-2xl cursor-pointer flex items-center justify-center">
              ›
            </button>
          )}
          <button onClick={() => setLightbox(null)}
            className="pressable absolute top-4 right-4 bg-white/15 border-none rounded-full w-8 h-8 text-white text-lg cursor-pointer flex items-center justify-center">
            ✕
          </button>
          {cur.label && (
            <div className="absolute bottom-4 left-1/2 -translate-x-1/2 bg-black/50 text-white text-sm px-3 py-1 rounded-md whitespace-nowrap">
              {cur.label}
            </div>
          )}
        </div>
      )}
    </>
  )
}
