import { NextRequest, NextResponse } from 'next/server';
import { createPublicClient, http, Address } from 'viem';
import { sepolia, mainnet } from 'viem/chains';

import stabilizerNftAbiJson from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json';
import stabilizerEscrowAbiJson from '@/contracts/out/StabilizerEscrow.sol/StabilizerEscrow.json';
import { getContractAddresses } from '@/lib/contracts';

const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;
const FACTOR_10000 = BigInt(10000);
const MAX_STABILIZERS_TO_CHECK = 10;

// In-memory cache
interface CacheEntry {
  data: {
    totalMintableEth: string;
    mintableUspdValue: string;
    timestamp: number;
  };
  expiry: number;
}

const cache = new Map<string, CacheEntry>();

// Get the appropriate chain and RPC URL
function getChainConfig(chainId: number) {
  switch (chainId) {
    case 1:
      return { chain: mainnet, rpcUrl: (process.env.RPC_URL || "https://mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8") };
    case 11155111:
      return { chain: sepolia, rpcUrl: process.env.SEPOLIA_RPC_URL };
    default:
      return { chain: sepolia, rpcUrl: process.env.SEPOLIA_RPC_URL };
  }
}

async function calculateMintableCapacity(chainId: number): Promise<{ totalMintableEth: string; mintableUspdValue: string; timestamp: number }> {
  const { chain, rpcUrl } = getChainConfig(chainId);
  
  if (!rpcUrl) {
    throw new Error(`No RPC URL configured for chain ${chainId}`);
  }

  const client = createPublicClient({
    chain,
    transport: http(rpcUrl),
  });

  // Get contract addresses
  const addresses = await getContractAddresses(chainId);
  if (!addresses?.stabilizer) {
    throw new Error(`No stabilizer contract address found for chain ${chainId}`);
  }

  const stabilizerNftAddress = addresses.stabilizer as Address;

  // Get current ETH/USD price
  const priceResponse = await fetch(`${process.env.NEXT_PUBLIC_BASE_URL || 'https://uspd.io'}/api/v1/price/eth-usd`);
  if (!priceResponse.ok) {
    throw new Error('Failed to fetch ETH price');
  }
  const priceData = await priceResponse.json();

  let currentTotalEthCanBeBacked = BigInt(0);

  try {
    // Get the lowest unallocated ID
    let currentTokenId = await client.readContract({
      address: stabilizerNftAddress,
      abi: stabilizerNftAbiJson.abi,
      functionName: 'lowestUnallocatedId',
    }) as bigint;

    // Iterate through unallocated stabilizers
    for (let i = 0; i < MAX_STABILIZERS_TO_CHECK && currentTokenId !== BigInt(0); i++) {
      const position = await client.readContract({
        address: stabilizerNftAddress,
        abi: stabilizerNftAbiJson.abi,
        functionName: 'positions',
        args: [currentTokenId],
      }) as [bigint, bigint, bigint, bigint, bigint];

      const minCollateralRatio = position[0];
      const nextUnallocatedTokenId = position[2];

      if (minCollateralRatio <= FACTOR_10000) {
        currentTokenId = nextUnallocatedTokenId;
        continue;
      }

      const stabilizerEscrowAddress = await client.readContract({
        address: stabilizerNftAddress,
        abi: stabilizerNftAbiJson.abi,
        functionName: 'stabilizerEscrows',
        args: [currentTokenId],
      }) as Address;

      if (stabilizerEscrowAddress === '0x0000000000000000000000000000000000000000') {
        currentTokenId = nextUnallocatedTokenId;
        continue;
      }
      
      const stabilizerStEthAvailable = await client.readContract({
        address: stabilizerEscrowAddress,
        abi: stabilizerEscrowAbiJson.abi,
        functionName: 'unallocatedStETH',
      }) as bigint;

      if (stabilizerStEthAvailable > BigInt(0)) {
        const denominator = BigInt(minCollateralRatio) - FACTOR_10000;
        
        if (denominator > BigInt(0)) {
          const userEthForStabilizer = (BigInt(stabilizerStEthAvailable) * FACTOR_10000) / denominator;
          currentTotalEthCanBeBacked += userEthForStabilizer;
        }
      }
      currentTokenId = nextUnallocatedTokenId;
    }

    // Calculate USPD value
    let mintableUspdValue = BigInt(0);
    if (currentTotalEthCanBeBacked > BigInt(0) && 
        priceData?.price && 
        typeof priceData?.decimals === 'number') {
      
      const ethPriceBigInt = BigInt(priceData.price);
      const priceDecimalsFactor = BigInt(10) ** BigInt(Math.floor(priceData.decimals));
      
      if (priceDecimalsFactor > BigInt(0)) {
        mintableUspdValue = (currentTotalEthCanBeBacked * ethPriceBigInt) / priceDecimalsFactor;
      }
    }

    return {
      totalMintableEth: currentTotalEthCanBeBacked.toString(),
      mintableUspdValue: mintableUspdValue.toString(),
      timestamp: Date.now(),
    };

  } catch (error) {
    console.error('Error calculating mintable capacity:', error);
    throw error;
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const chainId = parseInt(searchParams.get('chainId') || liquidityChainId.toString());
    
    const cacheKey = `mintable-capacity-${chainId}`;
    const now = Date.now();
    
    // Check cache
    const cached = cache.get(cacheKey);
    if (cached && now < cached.expiry) {
      return NextResponse.json(cached.data);
    }
    
    // Calculate new data
    const result = await calculateMintableCapacity(chainId);
    
    // Cache for 30 seconds
    cache.set(cacheKey, {
      data: result,
      expiry: now + 30000, // 30 seconds
    });
    
    // Clean up expired entries periodically
    for (const [key, entry] of cache.entries()) {
      if (now >= entry.expiry) {
        cache.delete(key);
      }
    }
    
    return NextResponse.json(result);
    
  } catch (error) {
    console.error('API Error:', error);
    return NextResponse.json(
      { error: 'Failed to calculate mintable capacity' },
      { status: 500 }
    );
  }
}
