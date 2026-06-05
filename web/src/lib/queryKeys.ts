import type { FilterState } from '../types/game'
import type { DiscoverParams } from './api'

export const qk = {
  games:       (filters: FilterState) => ['games', filters] as const,
  game:        (id: number)           => ['game', id]        as const,
  collections: ()                     => ['collections']     as const,
  profile:     ()                     => ['profile']         as const,
  discover:    (p: DiscoverParams)    => ['discover', p]     as const,
}
