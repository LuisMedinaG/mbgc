import { lazy, Suspense } from 'react'
import { Navigate, Routes, Route } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import { useAuth } from './hooks/useAuth'
import Layout from './components/Layout'

const CollectionPage = lazy(() => import('./pages/CollectionPage'))
const GameDetailPage = lazy(() => import('./pages/GameDetailPage'))
const VibesPage = lazy(() => import('./pages/VibesPage'))
const ImportPage = lazy(() => import('./pages/ImportPage'))
const ImportCsvPage = lazy(() => import('./pages/ImportCsvPage'))
const ProfilePage = lazy(() => import('./pages/ProfilePage'))
const LoginPage = lazy(() => import('./pages/LoginPage'))

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
        <Route index element={<Suspense fallback={null}><CollectionPage /></Suspense>} />
        <Route path="games/:id" element={<Suspense fallback={null}><GameDetailPage /></Suspense>} />
        <Route path="vibes" element={<Suspense fallback={null}><VibesPage /></Suspense>} />
        <Route path="import" element={<Suspense fallback={null}><ImportPage /></Suspense>} />
        <Route path="import/csv" element={<Suspense fallback={null}><ImportCsvPage /></Suspense>} />
        <Route path="profile" element={<Suspense fallback={null}><ProfilePage /></Suspense>} />
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
