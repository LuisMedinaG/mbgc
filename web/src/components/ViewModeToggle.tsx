interface Props {
  viewMode: 'list' | 'grid'
  onChange: (mode: 'list' | 'grid') => void
}

export default function ViewModeToggle({ viewMode, onChange }: Props) {
  return (
    <div className="flex gap-1">
      <button
        onClick={() => onChange('list')}
        aria-label="List view"
        className={`w-8 h-8 rounded-md border border-edge flex items-center justify-center cursor-pointer text-sm transition-all ${
          viewMode === 'list' ? 'bg-accent text-white' : 'bg-surface text-muted'
        }`}
      >
        ☰
      </button>
      <button
        onClick={() => onChange('grid')}
        aria-label="Grid view"
        className={`w-8 h-8 rounded-md border border-edge flex items-center justify-center cursor-pointer text-sm transition-all ${
          viewMode === 'grid' ? 'bg-accent text-white' : 'bg-surface text-muted'
        }`}
      >
        ⊞
      </button>
    </div>
  )
}