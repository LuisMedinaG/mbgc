import { useState, useCallback } from 'react'
import type { FilterState } from '../types/game'
import { useGames } from '../hooks/useGames'
import FilterBar from '../components/FilterBar'
import ActiveFilters from '../components/ActiveFilters'
import ViewModeToggle from '../components/ViewModeToggle'
import LoadingSkeleton from '../components/LoadingSkeleton'
import ErrorMessage from '../components/ErrorMessage'
import GameList from '../components/GameList'
import GameGrid from '../components/GameGrid'
import EmptyState from '../components/EmptyState'

const EMPTY_FILTERS: FilterState = {
  search: '',
  category: '',
  players: '',
  playtime: '',
  weight: '',
}

export default function CollectionPage() {
  const [filters, setFilters] = useState<FilterState>(EMPTY_FILTERS)
  const [viewMode, setViewMode] = useState<'list' | 'grid'>('list')
  const { games, total, categories, loading, error, fetchGames } = useGames()

  const updateFilter = useCallback((key: keyof FilterState, value: string) => {
    setFilters(prev => {
      const next = { ...prev, [key]: value }
      fetchGames(next)
      return next
    })
  }, [fetchGames])

  const removeFilter = useCallback((key: keyof FilterState) => {
    setFilters(prev => {
      const next = { ...prev, [key]: '' }
      fetchGames(next)
      return next
    })
  }, [fetchGames])

  return (
    <div className="flex flex-col gap-3">
      <div className="pt-1">
        <h1 className="font-heading text-xl font-bold text-ink mb-0.5">
          Board Game Collection
        </h1>
        <p className="text-xs text-muted">
          {loading ? 'Loading…' : `${total} games · find your next play`}
        </p>
      </div>

      <FilterBar filters={filters} categories={categories} onChange={updateFilter} />

      <ActiveFilters filters={filters} onRemove={removeFilter} />

      <div className="flex items-center justify-between">
        <span className="text-xs text-muted">
          {loading ? '' : `${games.length} ${games.length === 1 ? 'game' : 'games'}`}
        </span>
        <ViewModeToggle viewMode={viewMode} onChange={setViewMode} />
      </div>

      {loading && <LoadingSkeleton />}

      {!loading && error && <ErrorMessage message={error} />}

      {!loading && !error && (
        games.length === 0 ? (
          <EmptyState />
        ) : viewMode === 'list' ? (
          <GameList games={games} />
        ) : (
          <GameGrid games={games} />
        )
      )}
    </div>
  )
}
