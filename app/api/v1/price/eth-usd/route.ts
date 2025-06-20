import { NextResponse } from 'next/server';
import { PriceResponse } from '@/app/api/types/price';
import { SigningService } from '@/lib/signing';
import { keccak256, stringToHex } from 'viem';
import Redis from 'ioredis';

// Redis client setup
// Make sure to set REDIS_HOST/REDIS_PORT/REDIS_PASSWORD in your environment
const redis = new Redis(process.env.REDIS_PORT ? parseInt(process.env.REDIS_PORT, 10) : 6379, process.env.REDIS_HOST || 'localhost', {
    password: process.env.REDIS_PASSWORD,
    tls: {
        checkServerIdentity: () => { return undefined; },
    }
});

// Cache duration in milliseconds (5 seconds)
const CACHE_DURATION = 5000;
let cachedResponse: PriceResponse | null = null;
let lastFetchTime = 0;

// Price decimals to use (18 for Ethereum standard)
const PRICE_DECIMALS = 18;

export async function GET() {
    try {
        const now = Date.now();

        // Return cached response if valid
        if (cachedResponse && (now - lastFetchTime) < CACHE_DURATION) {
            return NextResponse.json(cachedResponse);
        }

        // Fetch new price from Redis
        const priceFromRedis = await redis.hget('markets:CRYPTO_ETH', 'close');

        if (!priceFromRedis) {
            throw new Error('Failed to fetch price from Redis: key "markets:CRYPTO_ETH" with field "close" not found.');
        }

        const dataTimestamp = Date.now();

        // Convert price to 18 decimals (multiply by 10^18)
        // Use a more precise conversion to avoid scientific notation issues
        const priceInWei = BigInt(Math.round(parseFloat(priceFromRedis) * 10 ** PRICE_DECIMALS)).toString();

        // Create asset pair string - this will be hashed in the contract
        const assetPairString = 'MORPHER:ETH_USD';

        const signingService = new SigningService();

        // Create and sign response
        const priceResponse: PriceResponse = {
            price: priceInWei,
            dataTimestamp: dataTimestamp,
            requestTimestamp: now,
            assetPair: keccak256(stringToHex(assetPairString)),
            signature: await signingService.signPriceData(
                priceInWei,
                dataTimestamp,
                assetPairString
            ),
            decimals: PRICE_DECIMALS
        };

        // Update cache
        cachedResponse = priceResponse;
        lastFetchTime = now;

        return NextResponse.json(priceResponse);
    } catch (error) {
        console.error('Price fetch error:', error);
        return NextResponse.json(
            { error: 'Failed to fetch price data' },
            { status: 500 }
        );
    }
}
