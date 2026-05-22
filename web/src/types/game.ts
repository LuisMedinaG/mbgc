export interface Game {
  id: number
  bggId: number
  name: string
  description: string
  yearPublished: number
  image: string
  thumbnail: string
  minPlayers: number
  maxPlayers: number
  playTime: number
  categories: string[]
  mechanics: string[]
  types: string[]
  weight: number
  rating: number
  languageDependence: number
  recommendedPlayers: number[]
  rulesUrl: string
  vibes: string[]
}

export type PlayersFilter = '' | '1' | '2' | '2only' | '3' | '4' | '5plus'
export type PlaytimeFilter = '' | 'short' | 'medium' | 'long'
export type WeightFilter   = '' | 'light' | 'medium' | 'heavy'

export interface FilterState {
  search:   string
  category: string
  players:  PlayersFilter
  playtime: PlaytimeFilter
  weight:   WeightFilter
}
