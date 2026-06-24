import { useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'

export function useRulesUrl(gameId: number) {
  const client = useQueryClient()

  const updateRulesUrl = useMutation({
    mutationFn: (rulesUrl: string) => api.updateRulesUrl(gameId, rulesUrl),
    onSuccess:  () => client.invalidateQueries({ queryKey: qk.game(gameId) }),
  })

  return { updateRulesUrl }
}
