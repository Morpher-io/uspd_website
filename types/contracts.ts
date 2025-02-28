export namespace IPriceOracle {
  export interface PriceAttestationQueryStruct {
    assetPair: `0x${string}`;
    price: bigint;
    decimals: number;
    dataTimestamp: bigint;
    requestTimestamp: bigint;
    signature: `0x${string}`;
  }

  export interface PriceResponseStruct {
    price: bigint;
    decimals: number;
  }
}
