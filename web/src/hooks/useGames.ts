import { useState, useCallback, useEffect, useRef } from 'react'
import { api, type GamesListResponse } from '../lib/api'
import type { FilterState } from '../types/game'

export function useGames() {
  const [games, setGames] = useState<GamesListResponse['data']>([])
  const [total, setTotal] = useState(0)
  const [categories, setCategories] = useState<string[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const fetchGames = useCallback(async (filters: FilterState, immediate = false) => {
    if (!immediate && filters.search) {
      if (debounceRef.current) clearTimeout(debounceRef.current)
      debounceRef.current = setTimeout(() => fetchGames(filters, true), 300)
      return
    }

    setError('')
    try {
      const res = await api.listGames({
        q: filters.search || undefined,
        category: filters.category || undefined,
        players: filters.players || undefined,
        playtime: filters.playtime || undefined,
        weight: filters.weight || undefined,
        limit: 50,
        page: 1,
      })
      setGames(res.data)
      setTotal(res.total)
      if (res.categories.length > 0) setCategories(res.categories)
    } catch {
      setError('Failed to load games.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchGames({
      search: '',
      category: '',
      players: '',
      playtime: '',
      weight: '',
    }, true)
  }, [fetchGames])

  return { games, total, categories, loading, error, fetchGames }
}