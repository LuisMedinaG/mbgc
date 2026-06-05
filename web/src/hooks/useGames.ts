import { useQuery } from '@tanstack/react-query'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'
import { useDebounce } from './useDebounce'
import type { FilterState } from '../types/game'

// ref: collection.SEARCH.5 — search input debounced 300ms before triggering request
export function useGames(filters: FilterState) {
  const debouncedSearch = useDebounce(filters.search, 300)
  const effectiveFilters = { ...filters, search: debouncedSearch }

  const { data, isLoading, isError } = useQuery({
    queryKey: qk.games(effectiveFilters),
    queryFn: () => api.listGames({
      q:        effectiveFilters.search   || undefined,
      category: effectiveFilters.category || undefined,
      players:  effectiveFilters.players  || undefined,
      playtime: effectiveFilters.playtime || undefined,
      weight:   effectiveFilters.weight   || undefined,
      limit:    50,
      page:     1,
    }),
  })

  return {
    games:      data?.data       ?? [],
    total:      data?.total      ?? 0,
    categories: data?.categories ?? [],
    loading:    isLoading,
    error:      isError ? 'Failed to load games.' : '',
  }
}
