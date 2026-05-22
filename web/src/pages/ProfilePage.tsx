import { useState, useEffect } from 'react'
import { api, ApiError } from '../lib/api'

type Msg = { ok: boolean; text: string }

function SaveButton({ onClick, disabled, saving, label }: {
  onClick: () => void; disabled: boolean; saving: boolean; label: string
}) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="btn btn-primary pressable self-start disabled:opacity-50">
      {saving ? `${label}ing…` : label}
    </button>
  )
}

export default function ProfilePage() {
  const [username, setUsername] = useState('')
  const [bggUsername, setBggUsername] = useState('')
  const [bggInput, setBggInput] = useState('')
  const [bggSaving, setBggSaving] = useState(false)
  const [bggMsg, setBggMsg] = useState<Msg | null>(null)

  const [currentPw, setCurrentPw] = useState('')
  const [newPw, setNewPw] = useState('')
  const [pwSaving, setPwSaving] = useState(false)
  const [pwMsg, setPwMsg] = useState<Msg | null>(null)

  useEffect(() => {
    api.getProfile().then(p => {
      setUsername(p.username)
      setBggUsername(p.bgg_username ?? '')
      setBggInput(p.bgg_username ?? '')
    }).catch(() => {})
  }, [])

  async function saveBGG() {
    setBggSaving(true); setBggMsg(null)
    try {
      const r = await api.setBGGUsername(bggInput.trim())
      setBggUsername(r.bgg_username)
      setBggMsg({ ok: true, text: 'Saved' })
    } catch (e) {
      setBggMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Failed to save' })
    } finally { setBggSaving(false) }
  }

  async function changePassword() {
    setPwSaving(true); setPwMsg(null)
    try {
      await api.changePassword(currentPw, newPw)
      setPwMsg({ ok: true, text: 'Password changed' })
      setCurrentPw(''); setNewPw('')
    } catch (e) {
      setPwMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Failed to change password' })
    } finally { setPwSaving(false) }
  }

  return (
    <div className="flex flex-col gap-5 pt-1">
      <h1 className="font-heading text-[1.6rem] font-bold text-ink">Profile</h1>

      <section className="card p-5 flex flex-col gap-3">
        <div className="section-label">Account</div>
        <div>
          <div className="field-label">Username</div>
          <div className="text-[0.95rem] font-medium text-ink">{username || '—'}</div>
        </div>
      </section>

      <section className="card p-5 flex flex-col gap-3">
        <div className="section-label">BoardGameGeek</div>
        <div>
          <label htmlFor="bgg-username" className="field-label">BGG Username</label>
          <input id="bgg-username" className="form-input" value={bggInput}
            onChange={e => { setBggInput(e.target.value); setBggMsg(null) }}
            placeholder="your BGG username" autoCapitalize="none" autoCorrect="off" spellCheck={false} />
        </div>
        {bggMsg && (
          <div className={`text-sm ${bggMsg.ok ? 'text-[#059669]' : 'text-[#b91c1c]'}`}>{bggMsg.text}</div>
        )}
        <SaveButton onClick={saveBGG} disabled={bggSaving || bggInput.trim() === bggUsername}
          saving={bggSaving} label="Save" />
      </section>

      <section className="card p-5 flex flex-col gap-3">
        <div className="section-label">Change Password</div>
        <div>
          <label htmlFor="current-pw" className="field-label">Current password</label>
          <input id="current-pw" type="password" className="form-input" value={currentPw}
            onChange={e => { setCurrentPw(e.target.value); setPwMsg(null) }}
            autoComplete="current-password" />
        </div>
        <div>
          <label htmlFor="new-pw" className="field-label">New password</label>
          <input id="new-pw" type="password" className="form-input" value={newPw}
            onChange={e => { setNewPw(e.target.value); setPwMsg(null) }}
            autoComplete="new-password" />
        </div>
        {pwMsg && (
          <div className={`text-sm ${pwMsg.ok ? 'text-[#059669]' : 'text-[#b91c1c]'}`}>{pwMsg.text}</div>
        )}
        <SaveButton onClick={changePassword} disabled={pwSaving || !currentPw || !newPw}
          saving={pwSaving} label="Change Password" />
      </section>
    </div>
  )
}
