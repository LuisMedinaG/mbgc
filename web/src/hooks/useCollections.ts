import { useState, useCallback, useEffect } from 'react'
import { api, type Collection } from '../lib/api'

export function useCollections() {
  const [collections, setCollections] = useState<Collection[]>([])
  const [loading, setLoading] = useState(true)

  const fetchCollections = useCallback(async () => {
    try {
      const data = await api.listCollections()
      setCollections(data)
    } catch {
      // ignore
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchCollections()
  }, [fetchCollections])

  const createCollection = useCallback(async (name: string, description = '') => {
    const col = await api.createCollection(name, description)
    setCollections(prev => [...prev, col])
    return col
  }, [])

  const updateCollection = useCallback(async (id: number, name: string, description = '') => {
    const updated = await api.updateCollection(id, name, description)
    setCollections(prev => prev.map(c => c.id === id ? { ...c, name: updated.name } : c))
  }, [])

  const deleteCollection = useCallback(async (id: number) => {
    await api.deleteCollection(id)
    setCollections(prev => prev.filter(c => c.id !== id))
  }, [])

  return {
    collections,
    loading,
    createCollection,
    updateCollection,
    deleteCollection,
  }
}