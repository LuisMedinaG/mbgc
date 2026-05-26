import type { FilterState } from '../types/game'

const LABELS: Record<keyof FilterState, string> = {
  search: 'Search',
  category: 'Category',
  players: 'Players',
  playtime: 'Duration',
  weight: 'Complexity',
}

const VALUE_DISPLAY: Record<string, string> = {
  '1': 'Solo',
  '2': 'Up to 2',
  '2only': 'Exactly 2',
  '3': 'Up to 3',
  '4': 'Up to 4',
  '5plus': '5+',
  'short': '< 30 min',
  'medium': '30–60 min',
  'long': '> 60 min',
  'light': 'Light',
  'heavy': 'Heavy',
}

interface Props {
  filters: FilterState
  onRemove: (key: keyof FilterState) => void
}

export default function ActiveFilters({ filters, onRemove }: Props) {
  const active = (Object.keys(filters) as Array<keyof FilterState>).filter(k => filters[k] !== '')

  if (active.length === 0) return null

  return (
    <div className="flex flex-wrap gap-1.5 items-center">
      {active.map(key => {
        const raw = filters[key]
        const display = VALUE_DISPLAY[raw] ?? raw
        return (
          <span key={key} className="filter-chip">
            <span style={{ opacity: 0.8, fontSize: '0.72rem' }}>{LABELS[key]}:</span> {display}
            <button
              className="chip-remove"
              onClick={() => onRemove(key)}
              aria-label={`Remove ${LABELS[key]} filter`}
            >
              ×
            </button>
          </span>
        )
      })}
    </div>
  )
}
