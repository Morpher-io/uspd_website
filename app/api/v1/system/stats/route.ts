import { NextRequest, NextResponse } from 'next/server';
import { createPublicClient, http, Address } from 'viem';
import { sepolia, mainnet } from 'viem/chains';

import reporterAbiJson from '@/contracts/out/OvercollateralizationReporter.sol/OvercollateralizationReporter.json';
import uspdTokenAbiJson from '@/contracts/out/UspdToken.sol/USPDToken.json';
import cuspdTokenAbiJson from '@/contracts/out/cUSPDToken.sol/cUSPDToken.json';
import { getContractAddresses } from '@/lib/contracts';

const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;
const MAX_UINT256 = '115792089237316195423570985008687907853269984665640564039457584007913129639935';

// In-memory cache
interface StatsData {
  systemRatio: string;
  totalEthEquivalent: string;
  yieldFactorSnapshot: string;
  uspdTotalSupply: string;
  cuspdTotalSupply: string;
  ethPrice: string;
  priceDecimals: number;
  timestamp: number;
}
interface CacheEntry {
  data: StatsData;
  expiry: number;
}
const cache = new Map<string, CacheEntry>();

function getChainConfig(chainId: number) {
  switch (chainId) {
    case 1:
      return { chain: mainnet, rpcUrl: (process.env.RPC_URL || "https://mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8") };
    case 11155111:
      return { chain: sepolia, rpcUrl: process.env.SEPOLIA_RPC_URL };
    default:
      throw new Error(`Unsupported liquidity chainId: ${chainId}`);
  }
}

async function calculateStats(chainId: number): Promise<StatsData> {
  const { chain, rpcUrl } = getChainConfig(chainId);
  if (!rpcUrl) {
    throw new Error(`No RPC URL configured for chain ${chainId}`);
  }

  const client = createPublicClient({ chain, transport: http(rpcUrl) });
  
  const addresses = await getContractAddresses(chainId);
  if (!addresses?.reporter || !addresses?.uspdToken || !addresses?.cuspdToken) {
    throw new Error(`Contract addresses not found for chain ${chainId}`);
  }

  const reporterAddress = addresses.reporter as Address;
  const uspdTokenAddress = addresses.uspdToken as Address;
  const cuspdTokenAddress = addresses.cuspdToken as Address;

  // Get current ETH/USD price to calculate system ratio
  const priceResponse = await fetch(`${process.env.NEXT_PUBLIC_BASE_URL || 'https://uspd.io'}/api/v1/price/eth-usd`);
  if (!priceResponse.ok) {
    throw new Error('Failed to fetch ETH price');
  }
  const priceData = await priceResponse.json();
  const priceResponseForContract = {
    price: BigInt(priceData.price),
    decimals: Number(priceData.decimals),
    timestamp: BigInt(priceData.dataTimestamp),
  };

  try {
    const contracts = [
      {
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'getSystemCollateralizationRatio',
        args: [priceResponseForContract],
      },
      {
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'totalEthEquivalentAtLastSnapshot',
      },
      {
        address: reporterAddress,
        abi: reporterAbiJson.abi,
        functionName: 'yieldFactorAtLastSnapshot',
      },
      {
        address: uspdTokenAddress,
        abi: uspdTokenAbiJson.abi,
        functionName: 'totalSupply',
      },
      {
        address: cuspdTokenAddress,
        abi: cuspdTokenAbiJson.abi,
        functionName: 'totalSupply',
      }
    ] as const;

    const results = await client.multicall({ contracts });

    const [
      systemRatioResult,
      totalEthEquivalentResult,
      yieldFactorSnapshotResult,
      uspdTotalSupplyResult,
      cuspdTotalSupplyResult
    ] = results;

    return {
      systemRatio: (systemRatioResult.result as bigint | undefined)?.toString() ?? MAX_UINT256,
      totalEthEquivalent: (totalEthEquivalentResult.result as bigint | undefined)?.toString() ?? '0',
      yieldFactorSnapshot: (yieldFactorSnapshotResult.result as bigint | undefined)?.toString() ?? '0',
      uspdTotalSupply: (uspdTotalSupplyResult.result as bigint | undefined)?.toString() ?? '0',
      cuspdTotalSupply: (cuspdTotalSupplyResult.result as bigint | undefined)?.toString() ?? '0',
      ethPrice: priceData.price,
      priceDecimals: priceData.decimals,
      timestamp: Date.now(),
    };

  } catch (error) {
    console.error('Error calculating system stats:', error);
    throw error;
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const chainId = parseInt(searchParams.get('chainId') || liquidityChainId.toString());
    
    const cacheKey = `system-stats-${chainId}`;
    const now = Date.now();
    
    // Check cache
    const cached = cache.get(cacheKey);
    if (cached && now < cached.expiry) {
      return NextResponse.json(cached.data);
    }
    
    // Calculate new data
    const result = await calculateStats(chainId);
    
    // Cache for 30 seconds
    cache.set(cacheKey, {
      data: result,
      expiry: now + 30000,
    });
    
    // Clean up expired entries
    for (const [key, entry] of cache.entries()) {
      if (now >= entry.expiry) {
        cache.delete(key);
      }
    }
    
    return NextResponse.json(result);
    
  } catch (error) {
    console.error('API Error:', error);
    return NextResponse.json(
      { error: 'Failed to calculate system stats' },
      { status: 500 }
    );
  }
}
