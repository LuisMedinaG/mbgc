interface Props {
  label: string
  tags: string[]
  variant: 'type' | 'category' | 'mechanic'
}

const CLASS_MAP = {
  type: 'tag tag-type',
  category: 'tag tag-category',
  mechanic: 'tag tag-mechanic',
}

export default function TagList({ label, tags, variant }: Props) {
  if (!tags || tags.length === 0) return null

  return (
    <div>
      <div className="field-label">{label}</div>
      <div className="flex flex-wrap gap-1.5">
        {tags.map(tag => (
          <span key={tag} className={CLASS_MAP[variant]}>{tag}</span>
        ))}
      </div>
    </div>
  )
}
