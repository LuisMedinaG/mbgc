import { useQuery } from '@tanstack/react-query'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'

export function useDiscover(collectionId: number | null) {
  const params = { collection_id: collectionId ?? 0 }
  const { data, isLoading, isFetching, isError } = useQuery({
    queryKey: qk.discover(params),
    queryFn:  () => api.discover(params),
    enabled:  collectionId !== null,
  })

  return {
    games:      data?.data ?? [],
    total:      data?.total ?? 0,
    collection: data?.collection ?? null,
    loading:    isLoading || isFetching,
    error:      isError ? 'Failed to load games.' : '',
  }
}
