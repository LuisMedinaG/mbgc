import { Link, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'

function TabBar() {
  const { pathname } = useLocation()
  const tabs = [
    { to: '/',        label: 'Collection', icon: '⊞' },
    { to: '/vibes',   label: 'Vibes',      icon: '✦' },
    { to: '/import',  label: 'Import',     icon: '⇩' },
    { to: '/profile', label: 'Profile',    icon: '⊙' },
  ]

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-50 flex border-t border-edge/60 backdrop-blur-xl bg-parchment/90"
      style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
    >
      {tabs.map(tab => {
        const active = tab.to === '/'
          ? pathname === '/' || pathname.startsWith('/games/')
          : pathname === tab.to || pathname.startsWith(tab.to + '/')
        return (
          <Link
            key={tab.to}
            to={tab.to}
            className={`pressable flex flex-1 flex-col items-center justify-center gap-[3px] py-2 pb-1 no-underline ${active ? 'text-accent' : 'text-muted'}`}
          >
            <span className="text-xl leading-none">{tab.icon}</span>
            <span className={`text-[0.62rem] uppercase tracking-wide ${active ? 'font-bold' : 'font-medium'}`}>
              {tab.label}
            </span>
          </Link>
        )
      })}
    </nav>
  )
}

export default function Layout() {
  const location = useLocation()
  const navigate = useNavigate()
  const { logout } = useAuth()
  const isDetail = location.pathname.startsWith('/games/')

  return (
    <div className="flex flex-col min-h-dvh">
      {/* Header */}
      <header
        className="sticky top-0 z-50 border-b border-edge/60 backdrop-blur-xl bg-parchment/90"
        style={{ paddingTop: 'env(safe-area-inset-top)' }}
      >
        <div className="h-[52px] max-w-2xl mx-auto w-full flex items-center relative px-4">
          {isDetail && (
            <button
              onClick={() => navigate(-1)}
              className="pressable absolute left-4 flex items-center gap-[3px] text-accent bg-transparent border-none cursor-pointer font-sans font-medium"
            >
              <span className="text-xl leading-none">‹</span>
              <span className="text-[0.9rem]">Collection</span>
            </button>
          )}

          <div className="flex-1 text-center">
            {!isDetail && (
              <Link to="/" className="inline-flex items-center gap-2 no-underline">
                <span className="text-lg">🎲</span>
                <span className="font-heading font-bold text-[1.05rem] text-ink tracking-tight">
                  My Collection
                </span>
              </Link>
            )}
          </div>

          {!isDetail && (
            <button
              onClick={() => logout()}
              className="pressable absolute right-4 text-muted bg-transparent border-none cursor-pointer text-[0.78rem] font-medium font-sans"
              aria-label="Sign out"
            >
              Sign out
            </button>
          )}
        </div>
      </header>

      {/* Page content */}
      <main
        className="flex-1 max-w-2xl mx-auto w-full px-4 pt-4"
        style={{ paddingBottom: 'calc(72px + env(safe-area-inset-bottom))' }}
      >
        <Outlet />
      </main>

      <TabBar />
    </div>
  )
}
