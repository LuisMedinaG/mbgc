import type { Game } from '../types/game'
import GameCard from './GameCard'

interface Props {
  games: Game[]
}

export default function GameGrid({ games }: Props) {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-3">
      {games.map(g => <GameCard key={g.id} game={g} />)}
    </div>
  )
}