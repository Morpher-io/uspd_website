import { ethers } from 'ethers';

export class SigningService {
    private signer: ethers.Wallet;
    
    constructor() {
        const privateKey = process.env.ORACLE_PRIVATE_KEY;
        if (!privateKey) {
            throw new Error('ORACLE_PRIVATE_KEY environment variable not set');
        }
        this.signer = new ethers.Wallet(privateKey);
    }

    async signPriceData(price: string, dataTimestamp: number, assetPair: string): Promise<string> {
        const message = ethers.utils.solidityKeccak256(
            ['string', 'uint256', 'string'],
            [price, dataTimestamp, assetPair]
        );
        
        const signature = await this.signer.signMessage(ethers.utils.arrayify(message));
        return signature;
    }
}

export const signingService = new SigningService();
