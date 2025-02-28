import { NextResponse } from 'next/server';
import { PriceResponse, BinanceResponse } from '@/app/api/types/price';
import { signingService } from '@/lib/signing';

// Cache duration in milliseconds (5 seconds)
const CACHE_DURATION = 5000;
let cachedResponse: PriceResponse | null = null;
let lastFetchTime = 0;

// Price decimals to use (18 for Ethereum standard)
const PRICE_DECIMALS = 18;

async function fetchBinancePrice(): Promise<BinanceResponse> {
    const response = await fetch('https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT');
    if (!response.ok) {
        throw new Error('Failed to fetch price from Binance');
    }
    const data = await response.json();
    return {
        symbol: data.symbol,
        price: data.price,
        timestamp: Date.now()
    };
}

export async function GET() {
    try {
        const now = Date.now();

        // Return cached response if valid
        if (cachedResponse && (now - lastFetchTime) < CACHE_DURATION) {
            return NextResponse.json(cachedResponse);
        }

        // Fetch new price
        const binanceData = await fetchBinancePrice();
        
        // Convert price to 18 decimals (multiply by 10^18)
        // Use a more precise conversion to avoid scientific notation issues
        const priceInWei = BigInt(Math.round(parseFloat(binanceData.price) * 10**PRICE_DECIMALS)).toString();
        
        // Create asset pair hash
        const assetPairString = 'MORPHER:ETH_USD';
        const assetPairHash = '0x' + Buffer.from(assetPairString).toString('hex');
        
        // Create and sign response
        const priceResponse: PriceResponse = {
            price: priceInWei,
            dataTimestamp: binanceData.timestamp,
            requestTimestamp: now,
            assetPair: assetPairHash,
            signature: await signingService.signPriceData(
                priceInWei,
                binanceData.timestamp,
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
