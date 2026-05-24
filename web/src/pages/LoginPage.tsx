import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { ApiError } from '../lib/api'

export default function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      await login(username, password)
      navigate('/', { replace: true })
    } catch (err) {
      setError(err instanceof ApiError && err.status === 401
        ? 'Invalid username or password.'
        : 'Something went wrong. Try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="min-h-dvh flex flex-col items-center justify-center bg-parchment p-6">
      <div className="w-full max-w-sm card p-8">
        <div className="text-center mb-7">
          <div className="text-4xl mb-2">🎲</div>
          <h1 className="font-heading text-[1.4rem] font-bold text-ink mb-1">My Board Game Collection</h1>
          <p className="text-xs text-muted">Sign in to your account</p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div>
            <label htmlFor="username" className="field-label">Username</label>
            <input id="username" type="text" value={username} onChange={e => setUsername(e.target.value)}
              autoComplete="username" required className="form-input" />
          </div>
          <div>
            <label htmlFor="password" className="field-label">Password</label>
            <input id="password" type="password" value={password} onChange={e => setPassword(e.target.value)}
              autoComplete="current-password" required className="form-input" />
          </div>
          {error && <div className="alert-error">{error}</div>}
          <button type="submit" disabled={submitting}
            className="btn btn-primary pressable mt-1 disabled:opacity-70">
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
