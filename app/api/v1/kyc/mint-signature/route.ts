import { NextRequest, NextResponse } from 'next/server';
import { SigningService } from '@/lib/signing';
import { keccak256, encodePacked } from 'viem';

// KYC signature response type
export type KYCSignatureResponse = {
    signature: string;
    nonce: number;
    to: string;
    sharesAmount: string;
    expiresAt: number;
};

export async function POST(request: NextRequest) {
    try {
        const body = await request.json();
        const { to, sharesAmount } = body;

        if (!to || !sharesAmount) {
            return NextResponse.json(
                { error: 'Missing required parameters: to, sharesAmount' },
                { status: 400 }
            );
        }

        // TODO: Check KYC status in database
        // For now, we'll assume all addresses are KYC'd for testing
        const isKYCd = await checkKYCStatus(to);
        if (!isKYCd) {
            return NextResponse.json(
                { error: 'Address not KYC verified' },
                { status: 403 }
            );
        }

        // Generate nonce as timestamp (in seconds)
        const nonce = Math.floor(Date.now() / 1000);
        const expiresAt = nonce + 300; // 5 minutes from now

        const signingService = new SigningService();

        // Create message hash for signature
        // keccak256(abi.encodePacked(to, sharesAmount, nonce))
        const messageHash = keccak256(
            encodePacked(
                ['address', 'uint256', 'uint256'],
                [to as `0x${string}`, BigInt(sharesAmount), BigInt(nonce)]
            )
        );

        // Sign the message hash
        const signature = await signingService.signMessage(messageHash);

        const response: KYCSignatureResponse = {
            signature,
            nonce,
            to,
            sharesAmount,
            expiresAt
        };

        return NextResponse.json(response);
    } catch (error) {
        console.error('KYC signature generation error:', error);
        return NextResponse.json(
            { error: 'Failed to generate KYC signature' },
            { status: 500 }
        );
    }
}

// Mock KYC check function - replace with actual database lookup
async function checkKYCStatus(address: string): Promise<boolean> {
    // TODO: Implement actual KYC database lookup
    // For now, return true for testing purposes
    console.log(`Checking KYC status for address: ${address}`);
    return true;
}
