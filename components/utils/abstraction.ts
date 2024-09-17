import { SafeAccountV0_2_0 as SafeAccount, getFunctionSelector, createCallData } from "abstractionkit";

export function getSmartAccountAddress(ownerPublicAddress: string) {
    const smartAccount = SafeAccount.initializeNewAccount([ownerPublicAddress]);
    return smartAccount.accountAddress;
}

export async function createMintUserOp(ownerPublicAddress: string, amount: bigint) {

    const smartAccount = SafeAccount.initializeNewAccount([ownerPublicAddress]);

    console.log("Account address (sender): " + smartAccount.accountAddress);

    const mintFunctionSignature = 'mint(address)';
    const mintFunctionSelector = getFunctionSelector(mintFunctionSignature);

    const mintTransactionCallData = createCallData(
        mintFunctionSelector,
        ["address"],
        [smartAccount.accountAddress]
    );
    console.log(mintTransactionCallData)
    const mintTransaction = {
        to: process.env.NEXT_PUBLIC_TOKEN_ADDRESS!,
        value: amount,
        data: mintTransactionCallData,
    }
    const mintUserOp = await smartAccount.createUserOperation(
        [mintTransaction],
        process.env.NEXT_PUBLIC_ETH_RPC!,
        process.env.NEXT_PUBLIC_BUNDLER_RPC!,
    )

    mintUserOp.verificationGasLimit = BigInt(Math.round(Number(mintUserOp.verificationGasLimit) * 1.2));
    // mintUserOp.maxFeePerGas = BigInt('20000000000');

    return mintUserOp;
}

export async function sendUserOperation(useroperation: any) {
    const smartAccount = new SafeAccount(useroperation.sender);
    return await smartAccount.sendUserOperation(useroperation, process.env.NEXT_PUBLIC_BUNDLER_RPC!);
}

export function createDataToSign(useroperation: any) {
    const domain = {
        chainId: 11155111,
        verifyingContract: '0xa581c4A4DB7175302464fF3C06380BC3270b4037',
    } as const

    const types = {
        SafeOp: [
            { type: "address", name: "safe" },
            { type: "uint256", name: "nonce" },
            { type: "bytes", name: "initCode" },
            { type: "bytes", name: "callData" },
            { type: "uint256", name: "callGasLimit" },
            { type: "uint256", name: "verificationGasLimit" },
            { type: "uint256", name: "preVerificationGas" },
            { type: "uint256", name: "maxFeePerGas" },
            { type: "uint256", name: "maxPriorityFeePerGas" },
            { type: "bytes", name: "paymasterAndData" },
            { type: "uint48", name: "validAfter" },
            { type: "uint48", name: "validUntil" },
            { type: "address", name: "entryPoint" },
        ],
    } as const

    const message = {
        safe: useroperation.sender,
        nonce: useroperation.nonce,
        initCode: useroperation.initCode,
        callData: useroperation.callData,
        callGasLimit: useroperation.callGasLimit,
        verificationGasLimit: useroperation.verificationGasLimit,
        preVerificationGas: useroperation.preVerificationGas,
        maxFeePerGas: useroperation.maxFeePerGas,
        maxPriorityFeePerGas: useroperation.maxPriorityFeePerGas,
        paymasterAndData: useroperation.paymasterAndData,
        validAfter: 0,
        validUntil: 0,
        entryPoint: "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789",
    } as const

    return { domain, types, message };
}

export function formatSignature(address: `0x${string}`, signature: string) {
    return SafeAccount.formatEip712SignaturesToUseroperationSignature([address], [signature]);
}
