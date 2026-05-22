import type { Game } from '../types/game'

export function playersStr(game: Game): string {
  if (game.minPlayers === game.maxPlayers) return `${game.minPlayers}`
  return `${game.minPlayers}–${game.maxPlayers}`
}

export function weightLabel(w: number): string {
  if (w < 2.0) return 'Light'
  if (w < 3.0) return 'Medium'
  return 'Heavy'
}

export function weightClass(w: number): string {
  if (w < 2.0) return 'weight-light'
  if (w < 3.0) return 'weight-medium'
  return 'weight-heavy'
}

export function imgFallback(name: string): string {
  return `https://placehold.co/200x200/d4c5a9/7a6a55?text=${encodeURIComponent(name)}`
}
