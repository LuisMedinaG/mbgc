import type { FilterState } from '../types/game'
import SearchInput from './SearchInput'

interface Props {
  filters: FilterState
  categories: string[]
  onChange: (key: keyof FilterState, value: string) => void
}

export default function FilterBar({ filters, categories, onChange }: Props) {
  return (
    <div className="flex flex-col gap-2">
      <SearchInput
        value={filters.search}
        onChange={v => onChange('search', v)}
      />

      <div className="flex flex-wrap gap-2">
        <select
          className="filter-select"
          value={filters.category}
          onChange={e => onChange('category', e.target.value)}
        >
          <option value="">All categories</option>
          {categories.map(c => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>

        <select
          className="filter-select"
          value={filters.players}
          onChange={e => onChange('players', e.target.value)}
        >
          <option value="">Any players</option>
          <option value="1">Solo (1)</option>
          <option value="2">Up to 2</option>
          <option value="2only">Exactly 2</option>
          <option value="3">Up to 3</option>
          <option value="4">Up to 4</option>
          <option value="5plus">5+</option>
        </select>

        <select
          className="filter-select"
          value={filters.playtime}
          onChange={e => onChange('playtime', e.target.value)}
        >
          <option value="">Any duration</option>
          <option value="short">&lt; 30 min</option>
          <option value="medium">30–60 min</option>
          <option value="long">&gt; 60 min</option>
        </select>

        <select
          className="filter-select"
          value={filters.weight}
          onChange={e => onChange('weight', e.target.value)}
        >
          <option value="">Any complexity</option>
          <option value="light">Light</option>
          <option value="medium">Medium</option>
          <option value="heavy">Heavy</option>
        </select>
      </div>
    </div>
  )
}
