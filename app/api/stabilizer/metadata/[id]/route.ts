import { NextRequest, NextResponse } from 'next/server';
import { 
    createPublicClient, 
    http, 
    formatUnits, 
    getAddress, 
    zeroAddress, 
    parseEther, 
    maxUint256 as MAX_UINT256_VIEM,
    Address
} from 'viem';
import { sepolia } from 'viem/chains'; // Assuming Sepolia based on RPC_URL

// --- IMPORTANT: CONFIGURE THESE VALUES ---
// Replace with your actual RPC URL (e.g., from environment variables)
const RPC_URL = process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org'; // Example for Sepolia

// Replace with your deployed contract addresses (e.g., from environment variables)
const STABILIZER_NFT_ADDRESS = process.env.STABILIZER_NFT_ADDRESS || '0xYourStabilizerNFTAddress';
const STETH_ADDRESS = process.env.STETH_ADDRESS || '0xYourStEthAddress'; // e.g., stETH on Sepolia or Mainnet
const INSURANCE_ESCROW_ADDRESS = process.env.INSURANCE_ESCROW_ADDRESS || '0xYourInsuranceEscrowAddress'; // Main Insurance Escrow

// --- ABI IMPORTS (ensure these paths are correct for your project) ---
import StabilizerNFTAbi from '@/contracts/out/StabilizerNFT.sol/StabilizerNFT.json';
import Erc20Abi from '@/contracts/out/ERC20.sol/ERC20.json'; // A standard ERC20 ABI
// Assuming InsuranceEscrow and PositionEscrow might have specific functions, otherwise ERC20 ABI for balance is fine.
// For simplicity, we'll use stETH.balanceOf(escrowAddress). If they have getStEthBalance(), import their ABIs.
// import InsuranceEscrowAbi from '@/contracts/out/InsuranceEscrow.sol/InsuranceEscrow.json';
// import PositionEscrowAbi from '@/contracts/out/PositionEscrow.sol/PositionEscrow.json';

const publicClient = createPublicClient({
  chain: sepolia, // Or dynamically determine based on RPC_URL if needed
  transport: http(RPC_URL),
});

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
  insuranceEscrowAddress,
  insuranceEscrowStEthBalance,
  positionEscrowAddress,
  positionEscrowStEthBalance,
  minCollateralRatioBps,
  currentCollateralRatioBps,
  mintedUspd,
  ethUsdPriceFormatted,
}: {
  tokenId: string;
  insuranceEscrowAddress: string;
  insuranceEscrowStEthBalance: bigint;
  positionEscrowAddress: string;
  positionEscrowStEthBalance: bigint;
  minCollateralRatioBps: bigint;
  currentCollateralRatioBps: bigint;
  mintedUspd: bigint;
  ethUsdPriceFormatted: string;
}): string {
  const width = 380;
  const height = 520;

  const formattedInsuranceEscrowStEth = formatBigIntDisplay(insuranceEscrowStEthBalance);
  const formattedPositionEscrowStEth = formatBigIntDisplay(positionEscrowStEthBalance);
  const formattedMintedUspd = formatBigIntDisplay(mintedUspd);
  
  const minCollateralRatioPercent = minCollateralRatioBps > 0n ? Number(minCollateralRatioBps) / 100 : 0;
  
  let currentCollateralRatioPercentText = "N/A";
  if (currentCollateralRatioBps === MAX_UINT256) {
    currentCollateralRatioPercentText = "Infinite (No Debt)";
  } else if (mintedUspd === 0n && positionEscrowStEthBalance > 0n) {
    currentCollateralRatioPercentText = "Infinite (No Debt)";
  } else if (mintedUspd === 0n && positionEscrowStEthBalance === 0n) {
    currentCollateralRatioPercentText = "0.00%";
  }
  else if (currentCollateralRatioBps > 0n) {
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

        <!-- Main Insurance Escrow Info -->
        <rect x="10" y="60" width="${width - 60}" height="70" rx="10" fill="url(#cardGradient)" stroke="#718096" stroke-opacity="0.5"/>
        <text x="25" y="85" font-family="sans-serif" font-size="14" fill="#a0aec0" font-weight="semibold">Main Insurance Escrow:</text>
        <text x="25" y="105" font-family="monospace" font-size="13" fill="#e2e8f0">${formatAddress(insuranceEscrowAddress)}</text>
        <text x="25" y="125" font-family="sans-serif" font-size="14" fill="#e2e8f0"><tspan font-weight="bold">${formattedInsuranceEscrowStEth}</tspan> stETH</text>

        <!-- Position Escrow Info -->
        <rect x="10" y="145" width="${width - 60}" height="70" rx="10" fill="url(#cardGradient)" stroke="#718096" stroke-opacity="0.5"/>
        <text x="25" y="170" font-family="sans-serif" font-size="14" fill="#a0aec0" font-weight="semibold">Position Escrow (NFT #${tokenId}):</text>
        <text x="25" y="190" font-family="monospace" font-size="13" fill="#e2e8f0">${formatAddress(positionEscrowAddress)}</text>
        <text x="25" y="210" font-family="sans-serif" font-size="14" fill="#e2e8f0"><tspan font-weight="bold">${formattedPositionEscrowStEth}</tspan> stETH</text>
        
        <!-- Position Details -->
        <rect x="10" y="230" width="${width - 60}" height="155" rx="10" fill="url(#cardGradient)" stroke="#718096" stroke-opacity="0.5"/>
        <text x="25" y="255" font-family="sans-serif" font-size="14" fill="#a0aec0" font-weight="semibold">Position Details (NFT #${tokenId}):</text>
        
        <text x="25" y="280" font-family="sans-serif" font-size="14" fill="#e2e8f0">Min. Collateral Ratio:</text>
        <text x="${width - 85}" y="280" font-family="sans-serif" font-size="14" fill="#e2e8f0" text-anchor="end" font-weight="bold">${minCollateralRatioPercent.toFixed(2)}%</text>

        <text x="25" y="305" font-family="sans-serif" font-size="14" fill="#e2e8f0">Minted USPD:</text>
        <text x="${width - 85}" y="305" font-family="sans-serif" font-size="14" fill="#e2e8f0" text-anchor="end" font-weight="bold">${formattedMintedUspd}</text>
        
        <text x="25" y="330" font-family="sans-serif" font-size="14" fill="#e2e8f0">Current Collateral Ratio:</text>
        <text x="${width - 85}" y="330" font-family="sans-serif" font-size="16" fill="${ratioColor}" text-anchor="end" font-weight="bold">${currentCollateralRatioPercentText}</text>
        
        <text x="25" y="355" font-family="sans-serif" font-size="12" fill="#a0aec0">ETH Price (Snapshot):</text>
        <text x="${width - 85}" y="355" font-family="sans-serif" font-size="12" fill="#a0aec0" text-anchor="end">${ethUsdPriceFormatted}</text>

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
  const tokenId = params.id;

  if (!tokenId || isNaN(parseInt(tokenId))) {
    return NextResponse.json({ error: 'Invalid token ID' }, { status: 400 });
  }

  try {
    // --- Fetch On-Chain Data ---
    let positionDataResult;
    try {
      // Assuming StabilizerNFTAbi.abi is a valid ABI array
      positionDataResult = await publicClient.readContract({
        address: STABILIZER_NFT_ADDRESS as Address,
        abi: StabilizerNFTAbi.abi,
        functionName: 'positions',
        args: [BigInt(tokenId)],
      });
    } catch (e: any) {
      console.error(`Error fetching position data for token ${tokenId}:`, e.message);
      return NextResponse.json({ error: `Token ID ${tokenId} not found or error fetching position data.` }, { status: 404 });
    }
    
    // Assuming `positions` returns a struct or named outputs that viem maps to an object.
    // If it returns a tuple, access would be by index e.g., positionDataResult[0]
    const positionData = positionDataResult as { minCollateralRatio: bigint, mintedUspdEquivalent: bigint };
    const minCollateralRatioBps: bigint = positionData.minCollateralRatio;
    const mintedUspdEquivalent: bigint = positionData.mintedUspdEquivalent; // This is 18 decimals

    let positionEscrowAddress: Address = zeroAddress;
    try {
      const rawPositionEscrowAddress = await publicClient.readContract({
        address: STABILIZER_NFT_ADDRESS as Address,
        abi: StabilizerNFTAbi.abi,
        functionName: 'positionEscrows',
        args: [BigInt(tokenId)],
      });
      positionEscrowAddress = getAddress(rawPositionEscrowAddress as string); // Checksum
    } catch (e: any) {
      console.warn(`Could not fetch positionEscrow for token ${tokenId}:`, e.message);
      // Non-critical, can proceed with ZeroAddress
    }
    
    const insuranceEscrowAddressChecksummed = getAddress(INSURANCE_ESCROW_ADDRESS as Address);

    let insuranceEscrowStEthBalance: bigint = 0n;
    if (insuranceEscrowAddressChecksummed !== zeroAddress) {
      try {
        insuranceEscrowStEthBalance = await publicClient.readContract({
            address: STETH_ADDRESS as Address,
            abi: Erc20Abi.abi,
            functionName: 'balanceOf',
            args: [insuranceEscrowAddressChecksummed]
        }) as bigint;
      } catch (e: any) {
        console.warn(`Could not fetch stETH balance for main insurance escrow ${insuranceEscrowAddressChecksummed}:`, e.message);
      }
    }

    let positionEscrowStEthBalance: bigint = 0n;
    if (positionEscrowAddress !== zeroAddress) {
      try {
        positionEscrowStEthBalance = await publicClient.readContract({
            address: STETH_ADDRESS as Address,
            abi: Erc20Abi.abi,
            functionName: 'balanceOf',
            args: [positionEscrowAddress]
        }) as bigint;
      } catch (e: any) {
        console.warn(`Could not fetch stETH balance for position escrow ${positionEscrowAddress}:`, e.message);
      }
    }
    
    // --- Fetch ETH-USD Price ---
    // Ensure the host is correct for your environment (e.g., localhost for dev, deployed URL for prod)
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
      ethUsdPrice = BigInt(priceData.price); // e.g., 300012345678 for $3000.12345678
      ethUsdPriceDecimals = Number(priceData.decimals); // e.g., 8
      ethUsdPriceFormatted = `$${(Number(ethUsdPrice) / (10**ethUsdPriceDecimals)).toFixed(2)}`;
    } catch (e: any) {
      console.error("Error fetching ETH-USD price:", e.message);
      // Continue with 0 price, ratios will be affected or N/A
    }

    // --- Calculate Current Collateralization Ratio ---
    let currentCollateralRatioBps: bigint = MAX_UINT256; // Default to MAX (Infinite)

    if (mintedUspdEquivalent > 0n && ethUsdPrice > 0n) {
      // Bring ETH price to 18 decimals for calculation with stETH balance (18 decimals)
      // Example: price is 3000_12345678 (8 decimals for $3000.12)
      // We want price * 10^(18-8) = price * 10^10
      const priceMultiplier = 10n ** BigInt(18 - ethUsdPriceDecimals);
      const ethUsdPrice18Dec = ethUsdPrice * priceMultiplier;

      // Collateral value in USD (18 decimals)
      // (positionEscrowStEthBalance * ethUsdPrice18Dec) / 10^18 (for stETH decimals)
      const collateralValueUsd18Dec = (positionEscrowStEthBalance * ethUsdPrice18Dec) / ONE_ETHER;
      
      // Ratio = (Collateral Value * 10000) / Debt Value
      currentCollateralRatioBps = (collateralValueUsd18Dec * BASIS_POINTS_DIVISOR) / mintedUspdEquivalent;
    } else if (mintedUspdEquivalent === 0n && positionEscrowStEthBalance > 0n) {
        currentCollateralRatioBps = MAX_UINT256; // No debt, some collateral = infinite ratio
    } else if (mintedUspdEquivalent === 0n && positionEscrowStEthBalance === 0n) {
        currentCollateralRatioBps = 0n; // No debt, no collateral = 0% or N/A
    }


    // --- Generate SVG ---
    const svgDataUri = generateStabilizerNFTSVG({
      tokenId,
      insuranceEscrowAddress: insuranceEscrowAddressChecksummed,
      insuranceEscrowStEthBalance,
      positionEscrowAddress,
      positionEscrowStEthBalance,
      minCollateralRatioBps,
      currentCollateralRatioBps,
      mintedUspd: mintedUspdEquivalent,
      ethUsdPriceFormatted,
    });

    // --- Construct Metadata ---
    const metadata = {
      name: `USPD Stabilizer NFT #${tokenId}`,
      description: `A position in the USPD Stabilizer system for token ID ${tokenId}. This NFT represents collateralized USPD.`,
      image: svgDataUri,
      attributes: [
        { trait_type: "Token ID", value: tokenId },
        { trait_type: "ETH Price (Snapshot)", value: ethUsdPriceFormatted },
        { trait_type: "Min Collateral Ratio", value: `${(Number(minCollateralRatioBps) / 100).toFixed(2)}%` },
        { 
          trait_type: "Current Collateral Ratio", 
          value: currentCollateralRatioBps === MAX_UINT256 ? "Infinite (No Debt)" : `${(Number(currentCollateralRatioBps) / 100).toFixed(2)}%`
        },
        { trait_type: "Minted USPD", value: formatBigIntDisplay(mintedUspdEquivalent, 18, 6) },
        { trait_type: "Position Escrow Address", value: formatAddress(positionEscrowAddress) },
        { trait_type: "Position Escrow Balance (stETH)", value: formatBigIntDisplay(positionEscrowStEthBalance, 18, 6) },
        { trait_type: "Main Insurance Escrow Address", value: formatAddress(insuranceEscrowAddressChecksummed) },
        { trait_type: "Main Insurance Escrow Balance (stETH)", value: formatBigIntDisplay(insuranceEscrowStEthBalance, 18, 6) },
      ],
    };

    return NextResponse.json(metadata);

  } catch (error: any) {
    console.error(`Failed to generate metadata for token ${tokenId}:`, error);
    return NextResponse.json({ error: 'Failed to generate metadata', details: error.message }, { status: 500 });
  }
}
