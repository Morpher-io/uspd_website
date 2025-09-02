'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Copy, ExternalLink } from "lucide-react"
import { DeploymentInfo } from '@/lib/contracts'

interface ChainInfo {
  name: string
  explorerUrl?: string
}

const CHAIN_INFO: Record<number, ChainInfo> = {
  1: { name: 'Ethereum Mainnet', explorerUrl: 'https://etherscan.io' },
  11155111: { name: 'Sepolia Testnet', explorerUrl: 'https://sepolia.etherscan.io' },
  10: { name: 'Optimism', explorerUrl: 'https://optimistic.etherscan.io' },
  56: { name: 'BNB Smart Chain', explorerUrl: 'https://bscscan.com' },
  137: { name: 'Polygon', explorerUrl: 'https://polygonscan.com' },
  324: { name: 'zkSync Era', explorerUrl: 'https://explorer.zksync.io' },
  42161: { name: 'Arbitrum One', explorerUrl: 'https://arbiscan.io' },
}

interface DeploymentData {
  chainId: number
  deployment: DeploymentInfo
}

export function DeploymentAddresses() {
  const [deployments, setDeployments] = useState<DeploymentData[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function loadDeployments() {
      try {
        const response = await fetch('/api/deployments')
        if (!response.ok) {
          throw new Error(`Failed to fetch deployments: ${response.statusText}`)
        }
        const data = await response.json()
        setDeployments(data)
      } catch (err) {
        console.error('Error loading deployments:', err)
        setError(err instanceof Error ? err.message : 'Failed to load deployments')
      } finally {
        setLoading(false)
      }
    }

    loadDeployments()
  }, [])

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text)
    } catch (err) {
      console.error('Failed to copy to clipboard:', err)
    }
  }

  const formatAddress = (address: string) => {
    return `${address.slice(0, 6)}...${address.slice(-4)}`
  }

  const getExplorerUrl = (chainId: number, address: string) => {
    const chainInfo = CHAIN_INFO[chainId]
    if (!chainInfo?.explorerUrl) return null
    return `${chainInfo.explorerUrl}/address/${address}`
  }

  if (loading) {
    return (
      <div className="flex justify-center items-center p-8">
        <p>Loading deployment data...</p>
      </div>
    )
  }

  if (error) {
    return (
      <Alert variant="destructive">
        <AlertDescription>
          {error}
        </AlertDescription>
      </Alert>
    )
  }

  if (deployments.length === 0) {
    return (
      <Alert>
        <AlertDescription>
          No deployments found.
        </AlertDescription>
      </Alert>
    )
  }

  return (
    <div className="space-y-6">
      {deployments.map(({ chainId, deployment }) => {
        const chainInfo = CHAIN_INFO[chainId] || { name: `Chain ${chainId}` }
        
        return (
          <Card key={chainId}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="flex items-center gap-2">
                    {chainInfo.name}
                    <Badge variant="outline">Chain ID: {chainId}</Badge>
                  </CardTitle>
                  <CardDescription>
                    Deployed on {new Date(deployment.metadata.deploymentTimestamp * 1000).toLocaleDateString()}
                  </CardDescription>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {/* Contracts */}
                <div>
                  <h4 className="font-semibold mb-2">Contracts</h4>
                  <div className="grid gap-2">
                    {Object.entries(deployment.contracts).map(([key, address]) => (
                      <div key={key} className="flex items-center justify-between p-2 bg-muted rounded">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-sm">{key}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-sm">{formatAddress(address)}</span>
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => copyToClipboard(address)}
                            className="h-6 w-6 p-0"
                          >
                            <Copy className="h-3 w-3" />
                          </Button>
                          {getExplorerUrl(chainId, address) && (
                            <Button
                              variant="ghost"
                              size="sm"
                              asChild
                              className="h-6 w-6 p-0"
                            >
                              <a
                                href={getExplorerUrl(chainId, address)!}
                                target="_blank"
                                rel="noopener noreferrer"
                              >
                                <ExternalLink className="h-3 w-3" />
                              </a>
                            </Button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Configuration */}
                <div>
                  <h4 className="font-semibold mb-2">Configuration</h4>
                  <div className="grid gap-2">
                    {Object.entries(deployment.config).map(([key, value]) => (
                      <div key={key} className="flex items-center justify-between p-2 bg-muted rounded">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-sm">{key}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          {typeof value === 'string' && value.startsWith('0x') ? (
                            <>
                              <span className="font-mono text-sm">{formatAddress(value)}</span>
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => copyToClipboard(value)}
                                className="h-6 w-6 p-0"
                              >
                                <Copy className="h-3 w-3" />
                              </Button>
                              {getExplorerUrl(chainId, value) && (
                                <Button
                                  variant="ghost"
                                  size="sm"
                                  asChild
                                  className="h-6 w-6 p-0"
                                >
                                  <a
                                    href={getExplorerUrl(chainId, value)!}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                  >
                                    <ExternalLink className="h-3 w-3" />
                                  </a>
                                </Button>
                              )}
                            </>
                          ) : (
                            <span className="font-mono text-sm">{String(value)}</span>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Metadata */}
                <div>
                  <h4 className="font-semibold mb-2">Deployment Metadata</h4>
                  <div className="grid gap-2">
                    <div className="flex items-center justify-between p-2 bg-muted rounded">
                      <span className="font-mono text-sm">deployer</span>
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-sm">{formatAddress(deployment.metadata.deployer)}</span>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => copyToClipboard(deployment.metadata.deployer)}
                          className="h-6 w-6 p-0"
                        >
                          <Copy className="h-3 w-3" />
                        </Button>
                        {getExplorerUrl(chainId, deployment.metadata.deployer) && (
                          <Button
                            variant="ghost"
                            size="sm"
                            asChild
                            className="h-6 w-6 p-0"
                          >
                            <a
                              href={getExplorerUrl(chainId, deployment.metadata.deployer)!}
                              target="_blank"
                              rel="noopener noreferrer"
                            >
                              <ExternalLink className="h-3 w-3" />
                            </a>
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}
