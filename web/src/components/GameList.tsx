import type { Game } from '../types/game'
import GameCard from './GameCard'
import GameListItem from './GameListItem'

interface Props {
  games: Game[]
  mode?: 'list' | 'grid'
}

export default function GameList({ games, mode = 'list' }: Props) {
  if (mode === 'grid') {
    return (
      <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-3">
        {games.map(g => <GameCard key={g.id} game={g} />)}
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-1.5">
      {games.map(g => <GameListItem key={g.id} game={g} />)}
    </div>
  )
}
