import { createContext, useEffect, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { api, setOnAuthFailure, tokens } from '../lib/api'

interface User {
  username: string
}

interface AuthContextValue {
  user: User | null
  loading: boolean
  login: (username: string, password: string) => Promise<void>
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export { AuthContext }

export function AuthProvider({ children }: { children: ReactNode }) {
  // Optimistic: if tokens exist, assume authenticated. Background ping fills in username
  // and will redirect to /login via onAuthFailure if the refresh token is expired.
  const [user, setUser] = useState<User | null>(() =>
    tokens.getAccess() ? { username: '' } : null,
  )
  const [loading, setLoading] = useState(!tokens.getAccess())
  const navigate = useNavigate()

  useEffect(() => {
    setOnAuthFailure(() => {
      setUser(null)
      navigate('/login', { replace: true })
    })
    api.ping()
      .then(data => setUser({ username: data.username }))
      .catch(() => setUser(null))
      .finally(() => setLoading(false))
  }, [navigate])

  async function login(username: string, password: string) {
    await api.login(username, password)
    const data = await api.ping()
    setUser({ username: data.username })
  }

  async function logout() {
    await api.logout()
    setUser(null)
    navigate('/login', { replace: true })
  }

  return (
    <AuthContext.Provider value={{ user, loading, login, logout }}>
      {children}
    </AuthContext.Provider>
  )
}
