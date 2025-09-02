import { NextResponse } from 'next/server'
import fs from 'fs'
import path from 'path'
import { DeploymentInfo } from '@/lib/contracts'

export async function GET() {
  try {
    const deploymentsDir = path.join(process.cwd(), 'contracts', 'deployments')
    
    if (!fs.existsSync(deploymentsDir)) {
      return NextResponse.json([])
    }

    const files = fs.readdirSync(deploymentsDir)
    const jsonFiles = files.filter(file => file.endsWith('.json'))
    
    const deployments = []
    
    for (const file of jsonFiles) {
      try {
        const chainId = parseInt(file.replace('.json', ''))
        if (isNaN(chainId)) continue
        
        const filePath = path.join(deploymentsDir, file)
        const fileContent = fs.readFileSync(filePath, 'utf8')
        const deployment: DeploymentInfo = JSON.parse(fileContent)
        
        deployments.push({
          chainId,
          deployment
        })
      } catch (error) {
        console.error(`Error reading deployment file ${file}:`, error)
        // Continue with other files
      }
    }
    
    // Sort by chain ID
    deployments.sort((a, b) => a.chainId - b.chainId)
    
    return NextResponse.json(deployments)
  } catch (error) {
    console.error('Error loading deployments:', error)
    return NextResponse.json(
      { error: 'Failed to load deployments' },
      { status: 500 }
    )
  }
}
