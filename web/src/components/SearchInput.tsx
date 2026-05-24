interface Props {
  value: string
  onChange: (value: string) => void
}

export default function SearchInput({ value, onChange }: Props) {
  return (
    <div className="relative w-full">
      <span className="absolute left-3 top-1/2 -translate-y-1/2 text-muted text-sm pointer-events-none">🔍</span>
      <input
        type="search"
        placeholder="Search games…"
        value={value}
        onChange={e => onChange(e.target.value)}
        className="w-full border border-edge rounded-md py-1.5 pl-10 pr-3 text-sm font-sans bg-surface text-ink outline-none focus:border-accent"
      />
    </div>
  )
}
