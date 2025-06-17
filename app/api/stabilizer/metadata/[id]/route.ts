import { NextRequest, NextResponse } from 'next/server';
import { 
    createPublicClient, 
    http, 
    formatUnits, 
    getAddress, 
    zeroAddress, 
    parseEther, 
    maxUint256 as MAX_UINT256_VIEM,
    Address,
    Chain
} from 'viem';
import { sepolia, mainnet } from 'viem/chains';
import { getDeploymentInfo } from '@/lib/contracts'; // Changed from getContractAddresses

// --- CONFIGURATION ---
const DEFAULT_CHAIN_ID = 11155111; // Sepolia

// Addresses will be loaded from deployment JSON files.

// --- ABI IMPORTS (ensure these paths are correct for your project) ---
import StabilizerNFTAbi from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json';
import Erc20Abi from '@/contracts/out/ERC20.sol/ERC20.json'; // A standard ERC20 ABI
import PositionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json';
import PoolSharesConversionRateAbi from '@/contracts/out/PoolSharesConversionRate.sol/PoolSharesConversionRate.json';
// InsuranceEscrowAbi is no longer needed as we fetch from the NFT-specific escrows.

// publicClient will be initialized within the GET handler based on TARGET_CHAIN_ID

const MAX_UINT256 = MAX_UINT256_VIEM;
const ONE_ETHER = parseEther("1"); // 10^18
const BASIS_POINTS_DIVISOR = 10000n; // For ratios like 11000 for 110%

// Helper to format address for display
function formatAddress(address: string | Address): string {
  if (!address || address === zeroAddress) return "N/A";
  try {
    const checksummedAddress = getAddress(address as Address);
    return `${checksummedAddress.substring(0, 6)}...${checksummedAddress.substring(checksummedAddress.length - 4)}`;
  } catch {
    return "Invalid Address";
  }
}

// Helper to format BigInt to a fixed decimal string
function formatBigIntDisplay(value: bigint | undefined, decimals: number = 18, precision: number = 4): string {
  if (value === undefined) return "N/A";
  return parseFloat(formatUnits(value, decimals)).toFixed(precision);
}

// Function to determine color based on collateralization ratio (BPS)
function getRatioColor(ratioBps: bigint): string {
  if (ratioBps === MAX_UINT256 || ratioBps === 0n) return "#9ca3af"; // Gray for N/A or Zero Debt
  if (ratioBps >= 15000n) return "#22c55e"; // Green (>= 150%)
  if (ratioBps >= 13000n) return "#eab308"; // Yellow (>= 130%)
  return "#ef4444"; // Red (< 130%)
}

// Function to generate the detailed SVG
function generateStabilizerNFTSVG({
  tokenId,
  ownerAddress,
  stabilizerEscrowAddress,
  stabilizerEscrowStEthBalance,
  minCollateralRatioBps,
  positionEscrowAddress,
  positionEscrowStEthBalance,
  backedPoolShares,
  uspdEquivalentFromShares,
  currentCollateralRatioBps,
  ethUsdPriceFormatted,
}: {
  tokenId: string;
  ownerAddress: Address;
  stabilizerEscrowAddress: Address;
  stabilizerEscrowStEthBalance: bigint;
  minCollateralRatioBps: bigint;
  positionEscrowAddress: string;
  positionEscrowStEthBalance: bigint;
  backedPoolShares: bigint;
  uspdEquivalentFromShares: bigint;
  currentCollateralRatioBps: bigint;
  ethUsdPriceFormatted: string;
}): string {
  const width = 380;
  const height = 560; // Adjusted height for new layout

  const formattedStabilizerEscrowStEth = formatBigIntDisplay(stabilizerEscrowStEthBalance);
  const formattedPositionEscrowStEth = formatBigIntDisplay(positionEscrowStEthBalance);
  const formattedBackedPoolShares = formatBigIntDisplay(backedPoolShares);
  const formattedUspdEquivalentFromShares = formatBigIntDisplay(uspdEquivalentFromShares);

  const minCollateralRatioPercent = minCollateralRatioBps > 0n ? Number(minCollateralRatioBps) / 100 : 0;
  
  let currentCollateralRatioPercentText = "N/A";
  if (currentCollateralRatioBps === MAX_UINT256) {
    currentCollateralRatioPercentText = "Infinite";
  } else if (uspdEquivalentFromShares === 0n && positionEscrowStEthBalance === 0n) {
    currentCollateralRatioPercentText = "0.00%";
  } else if (currentCollateralRatioBps > 0n) {
    currentCollateralRatioPercentText = `${(Number(currentCollateralRatioBps) / 100).toFixed(2)}%`;
  }

  const ratioColor = getRatioColor(currentCollateralRatioBps);

  const svg = `
    <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" fill="none" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="backgroundGradient" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" style="stop-color:#2d3748;stop-opacity:1" />
          <stop offset="100%" style="stop-color:#1a202c;stop-opacity:1" />
        </linearGradient>
        <linearGradient id="cardGradient" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" style="stop-color:#4a5568;stop-opacity:0.3" />
          <stop offset="100%" style="stop-color:#2d3748;stop-opacity:0.5" />
        </linearGradient>
      </defs>
      <rect width="100%" height="100%" rx="20" fill="url(#backgroundGradient)" />
      
      <g transform="translate(20, 20)">
        <text x="10" y="30" font-family="sans-serif" font-size="24" fill="#e2e8f0" font-weight="bold">USPD Stabilizer NFT #${tokenId}</text>
        <line x1="10" y1="45" x2="${width - 60}" y2="45" stroke="#4a5568" stroke-width="1"/>

        <!-- NFT Overview -->
        <rect x="10" y="60" width="${width - 60}" height="140" rx="10" fill="url(#cardGradient)" stroke="#718096" stroke-opacity="0.5"/>
        <text x="25" y="85" font-family="sans-serif" font-size="14" fill="#a0aec0" font-weight="semibold">NFT Overview</text>
        <text x="25" y="110" font-family="sans-serif" font-size="13" fill="#e2e8f0">Owner:</text>
        <text x="${width - 85}" y="110" font-family="monospace" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formatAddress(ownerAddress)}</text>
        <text x="25" y="135" font-family="sans-serif" font-size="13" fill="#e2e8f0">Stabilizer Escrow:</text>
        <text x="${width - 85}" y="135" font-family="monospace" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formatAddress(stabilizerEscrowAddress)}</text>
        <text x="25" y="160" font-family="sans-serif" font-size="13" fill="#e2e8f0">Min. Collateral Ratio:</text>
        <text x="${width - 85}" y="160" font-family="sans-serif" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${minCollateralRatioPercent.toFixed(2)}%</text>
        <text x="25" y="185" font-family="sans-serif" font-size="13" fill="#e2e8f0">Available Minting Collateral:</text>
        <text x="${width - 85}" y="185" font-family="sans-serif" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formattedStabilizerEscrowStEth} stETH</text>

        <!-- Position Escrow Details -->
        <rect x="10" y="215" width="${width - 60}" height="225" rx="10" fill="url(#cardGradient)" stroke="#718096" stroke-opacity="0.5"/>
        <text x="25" y="240" font-family="sans-serif" font-size="14" fill="#a0aec0" font-weight="semibold">Position Escrow Details (NFT #${tokenId})</text>
        <text x="25" y="265" font-family="sans-serif" font-size="13" fill="#e2e8f0">Address:</text>
        <text x="${width - 85}" y="265" font-family="monospace" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formatAddress(positionEscrowAddress)}</text>
        <text x="25" y="290" font-family="sans-serif" font-size="13" fill="#e2e8f0">Collateral:</text>
        <text x="${width - 85}" y="290" font-family="sans-serif" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formattedPositionEscrowStEth} stETH</text>
        <text x="25" y="315" font-family="sans-serif" font-size="13" fill="#e2e8f0">Liability (Shares):</text>
        <text x="${width - 85}" y="315" font-family="sans-serif" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formattedBackedPoolShares} cUSPD</text>
        <text x="25" y="340" font-family="sans-serif" font-size="13" fill="#e2e8f0">Liability (USPD Equivalent):</text>
        <text x="${width - 85}" y="340" font-family="sans-serif" font-size="13" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formattedUspdEquivalentFromShares} USPD</text>
        
        <line x1="25" y1="355" x2="${width - 75}" y2="355" stroke="#4a5568" stroke-width="0.5"/>

        <text x="25" y="375" font-family="sans-serif" font-size="14" fill="#e2e8f0">Current Collateral Ratio:</text>
        <text x="${width - 85}" y="375" font-family="sans-serif" font-size="16" fill="${ratioColor}" text-anchor="end" font-weight="bold">${currentCollateralRatioPercentText}</text>
        
        <text x="25" y="405" font-family="sans-serif" font-size="12" fill="#a0aec0">ETH Price (Snapshot):</text>
        <text x="${width - 85}" y="405" font-family="sans-serif" font-size="12" fill="#a0aec0" text-anchor="end">${ethUsdPriceFormatted}</text>

        <!-- Footer Text -->
        <text x="${(width-40)/2}" y="${height - 50}" font-family="sans-serif" font-size="10" fill="#718096" text-anchor="middle">USPD Protocol Stabilizer Position</text>
      </g>
    </svg>
  `;
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
}


export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  const tokenId = (await params).id;

  if (!tokenId || isNaN(parseInt(tokenId))) {
    return NextResponse.json({ error: 'Invalid token ID' }, { status: 400 });
  }

  try {
    // --- Determine Chain & RPC ---
    const targetChainIdStr = process.env.METADATA_CHAIN_ID;
    const targetChainId = targetChainIdStr ? parseInt(targetChainIdStr, 10) : DEFAULT_CHAIN_ID;

    let viemChain: Chain;
    let rpcUrl: string | undefined;

    if (targetChainId === sepolia.id) {
      viemChain = sepolia;
      rpcUrl = process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com';
    } else if (targetChainId === mainnet.id) {
      viemChain = mainnet;
      rpcUrl = process.env.MAINNET_RPC_URL; // User must set this
    } else {
      return NextResponse.json({ error: `Unsupported chain ID: ${targetChainId}` }, { status: 500 });
    }

    if (!rpcUrl) {
      return NextResponse.json({ error: `RPC URL not configured for chain ID ${targetChainId}` }, { status: 500 });
    }

    const publicClient = createPublicClient({
      chain: viemChain,
      transport: http(rpcUrl),
    });

    // --- Load Contract Addresses ---
    const deploymentInfo = await getDeploymentInfo(targetChainId);

    if (!deploymentInfo) {
      return NextResponse.json({ error: `Deployment info not found for chain ID ${targetChainId}` }, { status: 500 });
    }
    if (!deploymentInfo.contracts || !deploymentInfo.config) {
      return NextResponse.json({ error: `Incomplete deployment info for chain ID ${targetChainId}` }, { status: 500 });
    }

    const stabilizerNftAddress = deploymentInfo.contracts.stabilizer as Address | undefined;
    const stEthAddress = deploymentInfo.config.stETHAddress as Address | undefined; 
    const rateContractAddress = deploymentInfo.contracts.rateContract as Address | undefined;

    if (!stabilizerNftAddress) {
      return NextResponse.json({ error: `Stabilizer NFT contract address not found in deployment for chain ID ${targetChainId}` }, { status: 500 });
    }
    if (!stEthAddress) {
      return NextResponse.json({ error: `stETH address not found in deployment config for chain ID ${targetChainId}` }, { status: 500 });
    }
    if (!rateContractAddress) {
      return NextResponse.json({ error: `RateContract address not found in deployment for chain ID ${targetChainId}` }, { status: 500 });
    }

    // --- Fetch On-Chain Data ---
    let positionDataResult;
    try {
      positionDataResult = await publicClient.readContract({
        address: stabilizerNftAddress,
        abi: StabilizerNFTAbi.abi,
        functionName: 'positions',
        args: [BigInt(tokenId)],
      });
    } catch (e: any) {
      console.error(`Error fetching position data for token ${tokenId} on chain ${targetChainId}:`, e.message);
      return NextResponse.json({ error: `Token ID ${tokenId} not found or error fetching position data.` }, { status: 404 });
    }
    
    const positionTuple = positionDataResult as [bigint, bigint, bigint, bigint, bigint, bigint];
    const minCollateralRatioBps: bigint = positionTuple[0];

    let ownerAddress: Address = zeroAddress;
    try {
        ownerAddress = await publicClient.readContract({
            address: stabilizerNftAddress,
            abi: StabilizerNFTAbi.abi,
            functionName: 'ownerOf',
            args: [BigInt(tokenId)],
        }) as Address;
    } catch (e: any) {
        console.warn(`Could not fetch owner for token ${tokenId} on chain ${targetChainId}:`, e.message);
    }

    let stabilizerEscrowAddress: Address = zeroAddress;
    try {
      const rawStabilizerEscrowAddress = await publicClient.readContract({
        address: stabilizerNftAddress,
        abi: StabilizerNFTAbi.abi,
        functionName: 'stabilizerEscrows',
        args: [BigInt(tokenId)],
      });
      stabilizerEscrowAddress = getAddress(rawStabilizerEscrowAddress as string);
    } catch (e: any) {
      console.warn(`Could not fetch stabilizerEscrow for token ${tokenId} on chain ${targetChainId}:`, e.message);
    }

    let positionEscrowAddress: Address = zeroAddress;
    try {
      const rawPositionEscrowAddress = await publicClient.readContract({
        address: stabilizerNftAddress,
        abi: StabilizerNFTAbi.abi,
        functionName: 'positionEscrows',
        args: [BigInt(tokenId)],
      });
      positionEscrowAddress = getAddress(rawPositionEscrowAddress as string);
    } catch (e: any) {
      console.warn(`Could not fetch positionEscrow for token ${tokenId} on chain ${targetChainId}:`, e.message);
    }
    
    let stabilizerEscrowStEthBalance: bigint = 0n;
    if (stabilizerEscrowAddress !== zeroAddress) {
      try {
        stabilizerEscrowStEthBalance = await publicClient.readContract({
            address: stEthAddress,
            abi: Erc20Abi.abi,
            functionName: 'balanceOf',
            args: [stabilizerEscrowAddress]
        }) as bigint;
      } catch (e: any) {
        console.warn(`Could not fetch stETH balance for stabilizer escrow ${stabilizerEscrowAddress} on chain ${targetChainId}:`, e.message);
      }
    }

    let positionEscrowStEthBalance: bigint = 0n;
    if (positionEscrowAddress !== zeroAddress) {
      try {
        positionEscrowStEthBalance = await publicClient.readContract({
            address: stEthAddress,
            abi: Erc20Abi.abi,
            functionName: 'balanceOf',
            args: [positionEscrowAddress]
        }) as bigint;
      } catch (e: any) {
        console.warn(`Could not fetch stETH balance for position escrow ${positionEscrowAddress} on chain ${targetChainId}:`, e.message);
      }
    }

    let backedPoolShares: bigint = 0n;
    if (positionEscrowAddress !== zeroAddress) {
        try {
            backedPoolShares = await publicClient.readContract({
                address: positionEscrowAddress,
                abi: PositionEscrowAbi.abi,
                functionName: 'backedPoolShares',
                args: [],
            }) as bigint;
        } catch (e: any) {
            console.warn(`Could not fetch backedPoolShares for position escrow ${positionEscrowAddress} on chain ${targetChainId}:`, e.message);
        }
    }

    let yieldFactor: bigint = ONE_ETHER; // Default to 1e18 (no yield effect)
    try {
        yieldFactor = await publicClient.readContract({
            address: rateContractAddress,
            abi: PoolSharesConversionRateAbi.abi,
            functionName: 'getYieldFactor',
            args: [],
        }) as bigint;
    } catch (e: any) {
        console.warn(`Could not fetch yieldFactor from ${rateContractAddress} on chain ${targetChainId}:`, e.message);
    }
    
    // --- Fetch ETH-USD Price ---
    const internalPriceApiUrl = `${process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'}/api/v1/price/eth-usd`;
    let ethUsdPrice = 0n;
    let ethUsdPriceDecimals = 8; // Default, should be overridden by API
    let ethUsdPriceFormatted = "N/A";

    try {
      const priceResponse = await fetch(internalPriceApiUrl);
      if (!priceResponse.ok) {
        throw new Error(`Failed to fetch ETH price: ${priceResponse.statusText}`);
      }
      const priceData = await priceResponse.json();
      ethUsdPrice = BigInt(priceData.price);
      ethUsdPriceDecimals = Number(priceData.decimals);
      ethUsdPriceFormatted = `$${(Number(ethUsdPrice) / (10**ethUsdPriceDecimals)).toFixed(2)}`;
    } catch (e: any) {
      console.error("Error fetching ETH-USD price:", e.message);
    }

    // --- Calculate Current Collateralization Ratio based on PositionEscrow's liability ---
    const uspdEquivalentFromShares = (backedPoolShares * yieldFactor) / ONE_ETHER;
    let currentCollateralRatioBps: bigint = MAX_UINT256; // Default to MAX (Infinite)

    if (uspdEquivalentFromShares > 0n && ethUsdPrice > 0n) {
      const priceMultiplier = 10n ** BigInt(18 - ethUsdPriceDecimals);
      const ethUsdPrice18Dec = ethUsdPrice * priceMultiplier;
      const collateralValueUsd18Dec = (positionEscrowStEthBalance * ethUsdPrice18Dec) / ONE_ETHER;
      
      currentCollateralRatioBps = (collateralValueUsd18Dec * BASIS_POINTS_DIVISOR) / uspdEquivalentFromShares;
    } else if (uspdEquivalentFromShares === 0n && positionEscrowStEthBalance > 0n) {
        currentCollateralRatioBps = MAX_UINT256; // No share liability, some collateral = infinite ratio
    } else if (uspdEquivalentFromShares === 0n && positionEscrowStEthBalance === 0n) {
        currentCollateralRatioBps = 0n; // No share liability, no collateral
    }

    // --- Generate SVG ---
    const svgDataUri = generateStabilizerNFTSVG({
      tokenId,
      ownerAddress,
      stabilizerEscrowAddress,
      stabilizerEscrowStEthBalance,
      minCollateralRatioBps,
      positionEscrowAddress,
      positionEscrowStEthBalance,
      backedPoolShares,
      uspdEquivalentFromShares,
      currentCollateralRatioBps,
      ethUsdPriceFormatted,
    });

    // --- Construct Metadata ---
    const metadata = {
      name: `USPD Stabilizer NFT #${tokenId}`,
      description: `A position in the USPD Stabilizer system for token ID ${tokenId}. This NFT represents collateralized USPD.`,
      image: svgDataUri,
      attributes: [
        { trait_type: "Token ID", value: tokenId },
        { trait_type: "Owner", value: formatAddress(ownerAddress) },
        { trait_type: "Stabilizer Escrow", value: formatAddress(stabilizerEscrowAddress) },
        { trait_type: "Position Escrow", value: formatAddress(positionEscrowAddress) },
        { trait_type: "Min Collateral Ratio", value: `${(Number(minCollateralRatioBps) / 100).toFixed(2)}%` },
        { trait_type: "Available Minting Collateral", value: `${formatBigIntDisplay(stabilizerEscrowStEthBalance, 18, 6)} stETH` },
        { 
          trait_type: "Current Collateral Ratio", 
          value: currentCollateralRatioBps === MAX_UINT256 ? "Infinite" : `${(Number(currentCollateralRatioBps) / 100).toFixed(2)}%`
        },
        { trait_type: "Position Escrow Collateral", value: `${formatBigIntDisplay(positionEscrowStEthBalance, 18, 6)} stETH` },
        { trait_type: "Position Escrow Liability (Shares)", value: formatBigIntDisplay(backedPoolShares, 18, 6) },
        { trait_type: "Position Escrow Liability (USPD)", value: formatBigIntDisplay(uspdEquivalentFromShares, 18, 6) },
        { trait_type: "ETH Price (Snapshot)", value: ethUsdPriceFormatted },
        { trait_type: "Current Yield Factor", value: formatBigIntDisplay(yieldFactor, 18, 5) },
      ],
    };

    return NextResponse.json(metadata);

  } catch (error: any) {
    console.error(`Failed to generate metadata for token ${tokenId}:`, error);
    return NextResponse.json({ error: 'Failed to generate metadata', details: error.message }, { status: 500 });
  }
}
