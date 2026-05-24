interface Props {
  message?: string
}

export default function EmptyState({ message = 'No games found. Try adjusting your filters.' }: Props) {
  return (
    <div className="text-center py-8 px-4 text-muted">
      <div className="text-5xl mb-3">🎲</div>
      <div className="font-heading text-lg mb-1">No games found</div>
      <div className="text-sm">{message}</div>
    </div>
  )
}