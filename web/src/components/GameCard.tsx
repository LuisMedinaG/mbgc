import { Link } from 'react-router-dom'
import type { Game } from '../types/game'
import { playersStr, weightClass, weightLabel, imgFallback } from '../utils/gameFormatters'

interface Props {
  game: Game
}

export default function GameCard({ game }: Props) {
  return (
    <Link
      to={`/games/${game.id}`}
      className="pressable flex flex-col bg-surface border border-edge rounded-xl overflow-hidden no-underline text-ink shadow-card"
    >
      <div className="aspect-square overflow-hidden">
        <img
          src={game.thumbnail}
          alt={game.name}
          onError={e => { e.currentTarget.src = imgFallback(game.name) }}
          className="w-full h-full object-cover block"
        />
      </div>

      <div className="p-3 flex-1 flex flex-col gap-1">
        <div className="font-heading font-semibold text-sm line-clamp-2 leading-tight">
          {game.name}
        </div>

        <div className="text-xs text-muted">
          {playersStr(game)}p · {game.playTime}m
        </div>

        <div className="flex items-center gap-1 mt-auto pt-0.5">
          <span className={weightClass(game.weight)}>{weightLabel(game.weight)}</span>
          <span className="ml-auto text-xs font-bold text-rating">
            ★ {game.rating.toFixed(1)}
          </span>
        </div>
      </div>
    </Link>
  )
}
