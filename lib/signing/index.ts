import { privateKeyToAccount } from 'viem/accounts'
import { keccak256, toHex, stringToHex, numberToHex, concat } from 'viem'

export class SigningService {
    private account;
    
    constructor() {
        const privateKey = process.env.ORACLE_PRIVATE_KEY;
        if (!privateKey) {
            throw new Error('ORACLE_PRIVATE_KEY environment variable not set');
        }
        this.account = privateKeyToAccount(privateKey as `0x${string}`);
    }

    async signPriceData(price: string, dataTimestamp: number, assetPair: string): Promise<string> {
        // Convert parameters to hex and concatenate
        const priceHex = stringToHex(price);
        const timestampHex = numberToHex(dataTimestamp);
        const assetPairHex = stringToHex(assetPair);
        
        // Create message hash
        const messageHash = keccak256(
            concat([priceHex, timestampHex, assetPairHex])
        );
        
        // Sign the message
        const signature = await this.account.signMessage({
            message: { raw: messageHash }
        });
        
        return signature;
    }
}

export const signingService = new SigningService();
