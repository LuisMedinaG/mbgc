import { useMutation } from '@tanstack/react-query'
import { api } from '../lib/api'

export function useImport() {
  const syncBGG = useMutation({
    mutationFn: (fullRefresh: boolean) => api.syncBGG(fullRefresh),
  })

  return { syncBGG }
}
