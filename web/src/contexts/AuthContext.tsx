import { createContext, useEffect, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { api, setOnAuthFailure } from '../lib/api'

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
  // Access tokens live in memory; initial load pings and may refresh via HttpOnly cookie.
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)
  // ref: auth.TOKEN_REFRESH.4 — refresh failure clears tokens and redirects to /login
  const navigate = useNavigate()

  useEffect(() => {
    // ref: auth.TOKEN_REFRESH.1 — 401 triggers token refresh
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
