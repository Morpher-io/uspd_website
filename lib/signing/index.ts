import { privateKeyToAccount } from 'viem/accounts'
import { keccak256, stringToHex, encodePacked } from 'viem'

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
        // Create the message hash that matches the contract's verification
        // The contract expects: keccak256(abi.encodePacked(price, decimals, timestamp, assetPair))
        const decimals = 18; // Using 18 decimals for price

        // Create the message hash that matches the contract's verification logic
        const messageHash = keccak256(
            encodePacked(
                ['uint256', 'uint8', 'uint256', 'bytes32'],
                [
                    BigInt(price),
                    decimals,
                    BigInt(dataTimestamp),
                    keccak256(stringToHex(assetPair))
                ]
            )
        );
        // Sign the message - this will automatically add the Ethereum Signed Message prefix
        const signature = await this.account.signMessage({
            message: { raw: messageHash }
        });

        return signature;
    }
}

export const signingService = new SigningService();
