import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { api, type PlayerAid } from '../lib/api'
import { qk } from '../lib/queryKeys'

export function usePlayerAids(gameId: number, initial: PlayerAid[]) {
  const client = useQueryClient()
  const [aids, setAids] = useState<PlayerAid[]>(initial)

  const uploadPlayerAid = useMutation({
    mutationFn: ({ file, label }: { file: File; label: string }) => api.uploadPlayerAid(gameId, file, label),
    onSuccess:  aid => {
      setAids(prev => [...prev, aid])
      client.invalidateQueries({ queryKey: qk.game(gameId) })
    },
  })

  const deletePlayerAid = useMutation({
    mutationFn: (aidID: number) => api.deletePlayerAid(gameId, aidID),
    onSuccess:  (_data, aidID) => {
      setAids(prev => prev.filter(a => a.id !== aidID))
      client.invalidateQueries({ queryKey: qk.game(gameId) })
    },
  })

  return { aids, uploadPlayerAid, deletePlayerAid }
}
