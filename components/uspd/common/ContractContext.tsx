'use client'

import React, { createContext, useContext, useState, ReactNode } from 'react'
import { getContractAddresses } from '@/lib/contracts'

interface ContractCache {
  [chainId: number]: {
    [key: string]: `0x${string}`
  }
}

interface ContractContextType {
  getContractAddress: (chainId: number, key: string) => `0x${string}` | null
  loadContracts: (chainId: number, keys: string[]) => Promise<Record<string, `0x${string}`> | null>
  isLoading: (chainId: number, keys: string[]) => boolean
}

const ContractContext = createContext<ContractContextType | undefined>(undefined)

export function ContractProvider({ children }: { children: ReactNode }) {
  const [cache, setCache] = useState<ContractCache>({})
  const [loadingStates, setLoadingStates] = useState<Record<string, boolean>>({})

  const getLoadingKey = (chainId: number, keys: string[]) => `${chainId}-${keys.sort().join(',')}`

  const getContractAddress = (chainId: number, key: string): `0x${string}` | null => {
    return cache[chainId]?.[key] || null
  }

  const isLoading = (chainId: number, keys: string[]): boolean => {
    const loadingKey = getLoadingKey(chainId, keys)
    return loadingStates[loadingKey] || false
  }

  const loadContracts = async (chainId: number, keys: string[]): Promise<Record<string, `0x${string}`> | null> => {
    const loadingKey = getLoadingKey(chainId, keys)
    
    // Check if all keys are already cached
    const cachedChain = cache[chainId]
    if (cachedChain && keys.every(key => cachedChain[key])) {
      const result: Record<string, `0x${string}`> = {}
      keys.forEach(key => {
        result[key] = cachedChain[key]
      })
      return result
    }

    // Avoid duplicate loading
    if (loadingStates[loadingKey]) {
      return null
    }

    setLoadingStates(prev => ({ ...prev, [loadingKey]: true }))

    try {
      const deploymentConfig = await getContractAddresses(chainId)
      if (!deploymentConfig) {
        throw new Error(`No deployment found for chain ID ${chainId}`)
      }

      const newAddresses: Record<string, `0x${string}`> = {}
      const missingKeys: string[] = []

      for (const key of keys) {
        const address = deploymentConfig[key as keyof typeof deploymentConfig]
        if (!address || address === '0x0000000000000000000000000000000000000000') {
          missingKeys.push(key)
        } else {
          newAddresses[key] = address as `0x${string}`
        }
      }

      if (missingKeys.length > 0) {
        throw new Error(`Contract address(es) not found for key(s): ${missingKeys.join(', ')} on chain ID ${chainId}`)
      }

      // Update cache
      setCache(prev => ({
        ...prev,
        [chainId]: {
          ...prev[chainId],
          ...newAddresses
        }
      }))

      return newAddresses
    } catch (error) {
      console.error('Error loading contracts:', error)
      throw error
    } finally {
      setLoadingStates(prev => ({ ...prev, [loadingKey]: false }))
    }
  }

  return (
    <ContractContext.Provider value={{ getContractAddress, loadContracts, isLoading }}>
      {children}
    </ContractContext.Provider>
  )
}

export function useContractContext() {
  const context = useContext(ContractContext)
  if (context === undefined) {
    throw new Error('useContractContext must be used within a ContractProvider')
  }
  return context
}
