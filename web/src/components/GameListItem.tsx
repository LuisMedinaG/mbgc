import { Link } from 'react-router-dom'
import type { Game } from '../types/game'
import { playersStr, weightClass, weightLabel, imgFallback } from '../utils/gameFormatters'

interface Props {
  game: Game
}

export default function GameListItem({ game }: Props) {
  return (
    <Link
      to={`/games/${game.id}`}
      className="pressable flex items-center gap-3 p-3 bg-surface border border-edge rounded-xl text-ink no-underline shadow-card"
    >
      <img
        src={game.thumbnail}
        alt={game.name}
        onError={e => { e.currentTarget.src = imgFallback(game.name) }}
        className="w-14 h-14 rounded-md object-cover flex-shrink-0"
      />

      <div className="flex-1 min-w-0">
        <div className="font-semibold text-sm overflow-hidden text-ellipsis whitespace-nowrap">
          {game.name}
        </div>
        <div className="text-xs text-muted mt-0.5">
          {playersStr(game)} players · {game.playTime} min
        </div>
        <div className="flex flex-wrap gap-1 mt-1">
          <span className={weightClass(game.weight)}>{weightLabel(game.weight)}</span>
          {game.vibes.map(v => (
            <span key={v} className="vibe-pill">{v}</span>
          ))}
        </div>
      </div>

      <div className="text-muted text-lg flex-shrink-0">›</div>
    </Link>
  )
}
