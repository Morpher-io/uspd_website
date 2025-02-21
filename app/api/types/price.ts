export type PriceResponse = {
    price: string;
    dataTimestamp: number;
    requestTimestamp: number;
    signature: string;
    assetPair: string;
}

export type BinanceResponse = {
    symbol: string;
    price: string;
    timestamp: number;
}
