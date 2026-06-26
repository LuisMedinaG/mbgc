import { useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'

export function useImport() {
  const client = useQueryClient()

  const previewBGG = useMutation({
    mutationFn: () => api.previewBGG(),
  })

  const syncBGG = useMutation({
    mutationFn: (fullRefresh: boolean) => api.syncBGG(fullRefresh),
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ['games'] })
      client.invalidateQueries({ queryKey: qk.collections() })
    },
  })

  // Create a list and drop the just-imported games into it.
  const createListWithGames = useMutation({
    mutationFn: async ({ name, gameIds }: { name: string; gameIds: number[] }) => {
      const col = await api.createCollection(name)
      if (gameIds.length) await api.bulkCollections(gameIds, [col.id])
      return col
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.collections() }),
  })

  return { previewBGG, syncBGG, createListWithGames }
}
