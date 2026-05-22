import { useMemo } from 'react'
import type { Game, FilterState } from '../types/game'

export function useFilteredGames(games: Game[], filters: FilterState): Game[] {
  return useMemo(() => {
    return games.filter(g => {
      // Text search — name, categories, mechanics
      if (filters.search) {
        const q = filters.search.toLowerCase()
        const searchable = [g.name, ...g.categories, ...g.mechanics].join(' ').toLowerCase()
        if (!searchable.includes(q)) return false
      }

      // Category filter
      if (filters.category && !g.categories.includes(filters.category)) {
        return false
      }

      // Players filter — mirrors Go filter.go logic
      if (filters.players) {
        switch (filters.players) {
          case '1':     if (g.minPlayers > 1) return false; break
          case '2':     if (g.minPlayers > 2) return false; break
          case '2only': if (g.minPlayers !== 2 || g.maxPlayers !== 2) return false; break
          case '3':     if (g.minPlayers > 3) return false; break
          case '4':     if (g.minPlayers > 4) return false; break
          case '5plus': if (g.maxPlayers < 5) return false; break
        }
      }

      // Playtime filter
      if (filters.playtime) {
        switch (filters.playtime) {
          case 'short':  if (g.playTime >= 30) return false; break
          case 'medium': if (g.playTime < 30 || g.playTime > 60) return false; break
          case 'long':   if (g.playTime <= 60) return false; break
        }
      }

      // Weight/complexity filter
      if (filters.weight) {
        switch (filters.weight) {
          case 'light':  if (g.weight === 0 || g.weight >= 2.0) return false; break
          case 'medium': if (g.weight < 2.0 || g.weight >= 3.0) return false; break
          case 'heavy':  if (g.weight < 3.0) return false; break
        }
      }

      return true
    })
  }, [games, filters])
}
