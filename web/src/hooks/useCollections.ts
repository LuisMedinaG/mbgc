import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'

export function useCollections() {
  const client = useQueryClient()

  const { data: collections = [], isLoading } = useQuery({
    queryKey: qk.collections(),
    queryFn:  api.listCollections,
  })

  function invalidate() {
    client.invalidateQueries({ queryKey: qk.collections() })
  }

  const createMut = useMutation({
    mutationFn: ({ name, description }: { name: string; description?: string }) =>
      api.createCollection(name, description),
    onSuccess: invalidate,
  })

  const updateMut = useMutation({
    mutationFn: ({ id, name, description }: { id: number; name: string; description?: string }) =>
      api.updateCollection(id, name, description),
    onSuccess: invalidate,
  })

  const deleteMut = useMutation({
    mutationFn: (id: number) => api.deleteCollection(id),
    onSuccess:  invalidate,
  })

  return {
    collections,
    loading:          isLoading,
    createCollection: (name: string, description?: string) =>
      createMut.mutateAsync({ name, description }),
    updateCollection: (id: number, name: string, description?: string) =>
      updateMut.mutateAsync({ id, name, description }),
    deleteCollection: (id: number) => deleteMut.mutateAsync(id),
  }
}
