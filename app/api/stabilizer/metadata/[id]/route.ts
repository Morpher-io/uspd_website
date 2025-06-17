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
  stabilizerEscrowStEthBalance,
  minCollateralRatioBps,
  positionEscrowAddress,
  positionEscrowStEthBalance,
  uspdEquivalentFromShares,
  currentCollateralRatioBps,
  ethUsdPriceFormatted,
}: {
  tokenId: string;
  stabilizerEscrowStEthBalance: bigint;
  minCollateralRatioBps: bigint;
  positionEscrowAddress: string;
  positionEscrowStEthBalance: bigint;
  uspdEquivalentFromShares: bigint;
  currentCollateralRatioBps: bigint;
  ethUsdPriceFormatted: string;
}): string {
  // Data formatting
  const formattedPositionEscrowStEth = formatBigIntDisplay(positionEscrowStEthBalance, 18, 4);
  const formattedUspdEquivalentFromShares = formatBigIntDisplay(uspdEquivalentFromShares, 18, 4);
  const formattedStabilizerEscrowStEth = formatBigIntDisplay(stabilizerEscrowStEthBalance, 18, 4);

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

  // Inlined USPD logo content from public/images/logo_uspd.svg
  const uspdLogoPaths = `
    <path fill-rule="evenodd" clip-rule="evenodd" d="M15.1415 8.00452L17.2121 15.7319C17.8791 18.2214 20.4381 19.6988 22.9276 19.0318C25.4171 18.3647 26.8945 15.8058 26.2274 13.3163L24.1568 5.58887L28.0205 4.5536L30.0911 12.281C31.1518 16.2395 29.293 20.2924 25.8347 22.1538L26.93 26.2415L23.0663 27.2768L21.971 23.1891C18.0453 23.3062 14.4091 20.7257 13.3484 16.7672L11.2778 9.03979L15.1415 8.00452Z" fill="#00C386"/>
    <path fill-rule="evenodd" clip-rule="evenodd" d="M44.7659 5.39508L39.1091 11.0519C37.2866 12.8744 37.2866 15.8291 39.1091 17.6516C40.9315 19.474 43.8863 19.474 45.7087 17.6516L51.3656 11.9947L54.194 14.8232L48.5372 20.48C45.6394 23.3778 41.2 23.7946 37.8588 21.7303L34.8664 24.7227L32.038 21.8942L35.0304 18.9018C32.9661 15.5606 33.3828 11.1213 36.2806 8.2235L41.9375 2.56665L44.7659 5.39508Z" fill="#00C386"/>
    <path fill-rule="evenodd" clip-rule="evenodd" d="M61.2919 29.3906L53.5645 27.32C51.075 26.6529 48.5161 28.1303 47.849 30.6198C47.1819 33.1093 48.6593 35.6683 51.1488 36.3353L58.8762 38.4059L57.841 42.2696L50.1136 40.199C46.1551 39.1383 43.5745 35.5021 43.6917 31.5764L39.6039 30.4811L40.6392 26.6174L44.7269 27.7127C46.5883 24.2544 50.6413 22.3956 54.5997 23.4563L62.3271 25.5269L61.2919 29.3906Z" fill="#00C386"/>
    <path fill-rule="evenodd" clip-rule="evenodd" d="M2.7091 34.6094L10.4365 36.68C12.926 37.3471 15.4849 35.8697 16.152 33.3802C16.819 30.8907 15.3417 28.3317 12.8521 27.6647L5.12475 25.5941L6.16003 21.7304L13.8874 23.801C17.8459 24.8617 20.4265 28.4979 20.3093 32.4236L24.397 33.5189L23.3618 37.3826L19.274 36.2873C17.4127 39.7456 13.3597 41.6044 9.40123 40.5437L1.67383 38.4731L2.7091 34.6094Z" fill="#00C386"/>
    <path fill-rule="evenodd" clip-rule="evenodd" d="M49.2862 56.0895L47.2156 48.3621C46.5486 45.8726 43.9897 44.3952 41.5002 45.0622C39.0107 45.7293 37.5333 48.2882 38.2003 50.7777L40.2709 58.5051L36.4072 59.5404L34.3366 51.813C33.276 47.8545 35.1347 43.8016 38.5931 41.9402L37.4978 37.8525L41.3615 36.8172L42.4568 40.9049C46.3825 40.7877 50.0187 43.3683 51.0793 47.3268L53.1499 55.0542L49.2862 56.0895Z" fill="#00C386"/>
    <path fill-rule="evenodd" clip-rule="evenodd" d="M19.6618 58.6989L25.3187 53.0421C27.1411 51.2196 27.1411 48.2648 25.3187 46.4424C23.4962 44.62 20.5414 44.62 18.719 46.4424L13.0621 52.0993L10.2337 49.2708L15.8906 43.614C18.7884 40.7162 23.2277 40.2994 26.5689 42.3637L29.5613 39.3713L32.3897 42.1998L29.3973 45.1922C31.4616 48.5334 31.0449 52.9727 28.1471 55.8705L22.4902 61.5273L19.6618 58.6989Z" fill="#00C386"/>
    <circle cx="32.0005" cy="32" r="3.75" fill="#00C386"/>
  `;

  // Helper for creating data point groups. This solves overlapping text and improves design.
  const createDataPoint = (x: number, y: number, label: string, value: string, unit = '', valueFontSize = 15) => {
    const unitSpan = unit ? `<tspan dx="5" font-size="12" fill="#a0aec0">${unit}</tspan>` : '';
    return `
      <g transform="translate(${x}, ${y})">
        <text x="0" y="0" font-family="sans-serif" font-size="13" fill="#a0aec0">${label}</text>
        <text x="0" y="20" font-family="sans-serif" font-size="${valueFontSize}" fill="#e2e8f0" font-weight="bold">
          ${value}${unitSpan}
        </text>
      </g>
    `;
  };

  const svg = `
    <svg viewBox="0 0 512 512" fill="none" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id="background" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">
          <stop offset="0%" stop-color="#1a202c" />
          <stop offset="100%" stop-color="#2d3748" />
        </radialGradient>
        <linearGradient id="card" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="rgba(74, 85, 104, 0.2)" />
          <stop offset="100%" stop-color="rgba(45, 55, 72, 0.4)" />
        </linearGradient>
      </defs>
      
      <rect width="512" height="512" rx="32" fill="url(#background)" />
      
      <!-- Header -->
      <g transform="translate(32, 32) scale(0.75)">
        ${uspdLogoPaths}
      </g>
      <text x="92" y="68" font-family="sans-serif" font-size="22" fill="#e2e8f0" font-weight="bold">Stabilizer NFT</text>
      <text x="480" y="58" font-family="monospace" font-size="28" fill="#a0aec0" text-anchor="end" font-weight="bold">#${tokenId}</text>
      
      <!-- Main Content: Collateral Ratio -->
      <g transform="translate(0, 110)">
        <text x="256" y="0" font-family="sans-serif" font-size="18" fill="#a0aec0" text-anchor="middle">Current Collateral Ratio</text>
        <text x="256" y="60" font-family="sans-serif" font-size="60" fill="${ratioColor}" text-anchor="middle" font-weight="bold">${currentCollateralRatioPercentText}</text>
      </g>
      
      <!-- Details Section -->
      <g transform="translate(32, 230)">
        <!-- Left Card: Position Details -->
        <rect x="0" y="0" width="220" height="180" rx="12" fill="url(#card)" stroke="#4a5568" stroke-opacity="0.3" />
        <text x="110" y="28" font-family="sans-serif" font-size="16" fill="#a0aec0" font-weight="semibold" text-anchor="middle">Position Details</text>
        <text x="110" y="48" font-family="monospace" font-size="13" fill="#718096" text-anchor="middle">${formatAddress(positionEscrowAddress)}</text>
        
        ${createDataPoint(15, 80, 'Collateral', formattedPositionEscrowStEth, 'stETH')}
        ${createDataPoint(15, 130, 'Liability', formattedUspdEquivalentFromShares, 'USPD')}

        <!-- Right Card: NFT Details -->
        <rect x="228" y="0" width="220" height="180" rx="12" fill="url(#card)" stroke="#4a5568" stroke-opacity="0.3" />
        <text x="338" y="28" font-family="sans-serif" font-size="16" fill="#a0aec0" font-weight="semibold" text-anchor="middle">NFT Details</text>

        ${createDataPoint(243, 60, 'Min. Ratio', `${minCollateralRatioPercent.toFixed(2)}%`)}
        ${createDataPoint(243, 110, 'Available to Mint', formattedStabilizerEscrowStEth, 'stETH')}
      </g>
      
      <!-- Footer -->
      <text x="32" y="450" font-family="sans-serif" font-size="13" fill="#a0aec0">ETH Price (Snapshot): ${ethUsdPriceFormatted}</text>
      <text x="480" y="450" font-family="sans-serif" font-size="13" fill="#718096" text-anchor="end">USPD Protocol</text>
    </svg>
  `;
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
}


export async function GET(
  _request: NextRequest,
  { params }: { params: { id: string } }
) {
  const tokenId = params.id;


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
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : String(e);
      console.error(`Error fetching position data for token ${tokenId} on chain ${targetChainId}:`, message);
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
    } catch (e: unknown) {
        const message = e instanceof Error ? e.message : String(e);
        console.warn(`Could not fetch owner for token ${tokenId} on chain ${targetChainId}:`, message);
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
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn(`Could not fetch stabilizerEscrow for token ${tokenId} on chain ${targetChainId}:`, message);
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
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : String(e);
      console.warn(`Could not fetch positionEscrow for token ${tokenId} on chain ${targetChainId}:`, message);
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
      } catch (e: unknown) {
        const message = e instanceof Error ? e.message : String(e);
        console.warn(`Could not fetch stETH balance for stabilizer escrow ${stabilizerEscrowAddress} on chain ${targetChainId}:`, message);
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
      } catch (e: unknown) {
        const message = e instanceof Error ? e.message : String(e);
        console.warn(`Could not fetch stETH balance for position escrow ${positionEscrowAddress} on chain ${targetChainId}:`, message);
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
        } catch (e: unknown) {
            const message = e instanceof Error ? e.message : String(e);
            console.warn(`Could not fetch backedPoolShares for position escrow ${positionEscrowAddress} on chain ${targetChainId}:`, message);
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
    } catch (e: unknown) {
        const message = e instanceof Error ? e.message : String(e);
        console.warn(`Could not fetch yieldFactor from ${rateContractAddress} on chain ${targetChainId}:`, message);
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
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : String(e);
      console.error("Error fetching ETH-USD price:", message);
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
      stabilizerEscrowStEthBalance,
      minCollateralRatioBps,
      positionEscrowAddress,
      positionEscrowStEthBalance,
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
        { trait_type: "Owner", value: ownerAddress === zeroAddress ? "N/A" : getAddress(ownerAddress) },
        { trait_type: "Stabilizer Escrow", value: stabilizerEscrowAddress === zeroAddress ? "N/A" : getAddress(stabilizerEscrowAddress) },
        { trait_type: "Position Escrow", value: positionEscrowAddress === zeroAddress ? "N/A" : getAddress(positionEscrowAddress) },
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

  } catch (error: unknown) {
    console.error(`Failed to generate metadata for token ${tokenId}:`, error);
    const details = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ error: 'Failed to generate metadata', details }, { status: 500 });
  }
}
