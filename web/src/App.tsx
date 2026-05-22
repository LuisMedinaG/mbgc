import { Navigate, Routes, Route } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import { useAuth } from './hooks/useAuth'
import Layout from './components/Layout'
import CollectionPage from './pages/CollectionPage'
import GameDetailPage from './pages/GameDetailPage'
import VibesPage from './pages/VibesPage'
import ImportPage from './pages/ImportPage'
import ImportCsvPage from './pages/ImportCsvPage'
import ProfilePage from './pages/ProfilePage'
import LoginPage from './pages/LoginPage'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return (
    <div className="min-h-dvh bg-parchment flex items-center justify-center">
      <div className="text-sm text-muted">Loading…</div>
    </div>
  )
  if (!user) return <Navigate to="/login" replace />
  return <>{children}</>
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <Layout />
          </RequireAuth>
        }
      >
        <Route index element={<CollectionPage />} />
        <Route path="games/:id" element={<GameDetailPage />} />
        <Route path="vibes" element={<VibesPage />} />
        <Route path="import" element={<ImportPage />} />
        <Route path="import/csv" element={<ImportCsvPage />} />
        <Route path="profile" element={<ProfilePage />} />
      </Route>
    </Routes>
  )
}

export default function App() {
  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  )
}
