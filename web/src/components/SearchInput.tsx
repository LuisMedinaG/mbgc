interface Props {
  value: string
  onChange: (value: string) => void
}

export default function SearchInput({ value, onChange }: Props) {
  return (
    <div className="relative w-full">
      <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-[1.125rem] h-[1.125rem] text-ink pointer-events-none" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.75">
        <circle cx="8.5" cy="8.5" r="5.5" />
        <line x1="13.5" y1="13.5" x2="18" y2="18" strokeLinecap="round" />
      </svg>
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
