import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../lib/api'
import { qk } from '../lib/queryKeys'

export function useProfile() {
  const client = useQueryClient()

  const { data: profile } = useQuery({
    queryKey: qk.profile(),
    queryFn:  api.getProfile,
  })

  const setBGGUsername = useMutation({
    mutationFn: (bggUsername: string) => api.setBGGUsername(bggUsername),
    onSuccess:  () => client.invalidateQueries({ queryKey: qk.profile() }),
  })

  const changePassword = useMutation({
    mutationFn: ({ currentPassword, newPassword }: { currentPassword: string; newPassword: string }) =>
      api.changePassword(currentPassword, newPassword),
  })

  return { profile, setBGGUsername, changePassword }
}
