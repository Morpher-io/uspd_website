import { NextRequest, NextResponse } from 'next/server';

// Placeholder function to generate a simple SVG data URI
// In a real scenario, this might involve more complex SVG generation or fetching from elsewhere
function generatePlaceholderSVG(tokenId: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400"><rect width="100%" height="100%" fill="black"/><text x="50%" y="50%" fill="white" font-size="20" text-anchor="middle" dominant-baseline="middle">Stabilizer #${tokenId}</text></svg>`;
  const base64Svg = Buffer.from(svg).toString('base64');
  return `data:image/svg+xml;base64,${base64Svg}`;
}

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  const tokenId = params.id;

  if (!tokenId || isNaN(parseInt(tokenId))) {
    return NextResponse.json({ error: 'Invalid token ID' }, { status: 400 });
  }

  // --- Placeholder Metadata ---
  // In a real implementation, you might fetch details related to the tokenId
  // from your contracts (using a provider like Alchemy/Infura) or a database/indexer.
  const metadata = {
    name: `USPD Stabilizer #${tokenId}`,
    description: "Represents a position in the USPD Stabilizer system.",
    image: generatePlaceholderSVG(tokenId), // Generate a simple placeholder SVG
    attributes: [
      {
        trait_type: "Token ID",
        value: tokenId,
      },
      // Add more attributes here based on actual on-chain or off-chain data
      // Example:
      // {
      //   trait_type: "Min Collateral Ratio",
      //   value: "110%" // Fetch actual value if needed
      // },
    ],
  };
  // --- End Placeholder Metadata ---

  return NextResponse.json(metadata);
}
