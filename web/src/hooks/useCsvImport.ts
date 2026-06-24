import { useMutation } from '@tanstack/react-query'
import { api } from '../lib/api'

export function useCsvImport() {
  const previewCSV = useMutation({
    mutationFn: (file: File) => api.csvPreview(file),
  })

  const importCSV = useMutation({
    mutationFn: (bggIDs: number[]) => api.csvImport(bggIDs),
  })

  return { previewCSV, importCSV }
}
