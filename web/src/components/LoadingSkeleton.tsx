export default function LoadingSkeleton() {
  return (
    <div className="flex flex-col gap-1.5">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="flex items-center gap-3 p-3 bg-surface border border-edge rounded-xl shadow-card">
          <div className="w-14 h-14 bg-edge rounded-md flex-shrink-0" />
          <div className="flex-1 flex flex-col gap-1">
            <div className="h-3.5 w-3/5 bg-edge rounded-sm" />
            <div className="h-3 w-2/5 bg-edge rounded-sm" />
          </div>
        </div>
      ))}
    </div>
  )
}