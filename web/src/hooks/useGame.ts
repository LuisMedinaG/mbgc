import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'

// ref: game-detail.DETAIL_VIEW.1 — fetches single game with collections and player aids
// ref: game-detail.VIBE_ASSIGN.1 — loads all user collections for checklist UI (parallel fetch)
export function useGame(id: number) {
  const client   = useQueryClient()
  const navigate = useNavigate()

  const gameQuery = useQuery({
    queryKey: qk.game(id),
    queryFn:  () => api.getGame(id),
    enabled:  id > 0,
  })

  const collectionsQuery = useQuery({
    queryKey: qk.collections(),
    queryFn:  api.listCollections,
    enabled:  id > 0,
  })

  // ref: game-detail.VIBE_ASSIGN.2 — calls POST /api/v1/games/{id}/collections with full ID set
  const saveVibes = useMutation({
    mutationFn: (collectionIds: number[]) => api.setGameCollections(id, collectionIds),
    onSuccess:  () => client.invalidateQueries({ queryKey: qk.game(id) }),
  })

  // ref: game-detail.DELETE.4 — navigates back to collection page on success
  const deleteGame = useMutation({
    mutationFn: () => api.deleteGame(id),
    onSuccess:  () => navigate('/'),
  })

  return {
    game:           gameQuery.data ?? null,
    allCollections: collectionsQuery.data ?? [],
    loading:        gameQuery.isLoading,
    error:          gameQuery.isError ? 'Game not found.' : '',
    saveVibes,
    deleteGame,
  }
}
