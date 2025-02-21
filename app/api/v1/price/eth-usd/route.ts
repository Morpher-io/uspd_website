import { NextResponse } from 'next/server';
import { PriceResponse, BinanceResponse } from '@/app/api/types/price';
import { signingService } from '@/lib/signing';

// Cache duration in milliseconds (1 second)
const CACHE_DURATION = 1000;
let cachedResponse: PriceResponse | null = null;
let lastFetchTime = 0;

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
        
        // Create and sign response
        const priceResponse: PriceResponse = {
            price: binanceData.price,
            dataTimestamp: binanceData.timestamp,
            requestTimestamp: now,
            assetPair: 'MORPHER:ETH_USD',
            signature: await signingService.signPriceData(
                binanceData.price,
                binanceData.timestamp,
                'MORPHER:ETH_USD'
            )
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
