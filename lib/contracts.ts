"use server"
import fs from 'fs';
import path from 'path';

export interface DeploymentInfo {
  contracts: {
    oracle: string;
    positionNFT: string;
    stabilizer: string;
    token: string;
  };
  config: {
    usdcAddress: string;
    uniswapRouter: string;
    chainlinkAggregator: string;
  };
  metadata: {
    chainId: number;
    deploymentTimestamp: number;
    deployer: string;
  };
}

export async function getDeploymentInfo(chainId: number): Promise<DeploymentInfo | null> {
  try {
    const filePath = path.join(process.cwd(), 'contracts', 'deployments', `${chainId}.json`);
    if (!fs.existsSync(filePath)) {
      console.warn(`No deployment found for chain ID ${chainId}`);
      return null;
    }
    
    const fileContent = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(fileContent) as DeploymentInfo;
  } catch (error) {
    console.error(`Error reading deployment info for chain ID ${chainId}:`, error);
    return null;
  }
}

export async function getContractAddresses(chainId: number): Promise<Record<string, string> | null> {
  const deploymentInfo = await getDeploymentInfo(chainId);
  if (!deploymentInfo) return null;
  
  return {
    oracle: deploymentInfo.contracts.oracle,
    positionNFT: deploymentInfo.contracts.positionNFT,
    stabilizer: deploymentInfo.contracts.stabilizer,
    token: deploymentInfo.contracts.token
  };
}
