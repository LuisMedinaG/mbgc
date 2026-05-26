import type { Game } from '../types/game'
import GameListItem from './GameListItem'

interface Props {
  games: Game[]
}

export default function GameList({ games }: Props) {
  return (
    <div className="flex flex-col gap-1.5">
      {games.map(g => <GameListItem key={g.id} game={g} />)}
    </div>
  )
}