import { SafeAccountV0_3_0 as SafeAccount, getFunctionSelector, createCallData } from "abstractionkit";

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
        verifyingContract: '0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226',
    } as const

    const types = {
        SafeOp: [
            { type: "address", name: "safe" },
            { type: "uint256", name: "nonce" },
            { type: "bytes", name: "initCode" },
            { type: "bytes", name: "callData" },
            { type: "uint128", name: "verificationGasLimit" },
            { type: "uint128", name: "callGasLimit" },
            { type: "uint256", name: "preVerificationGas" },
            { type: "uint128", name: "maxPriorityFeePerGas" },
            { type: "uint128", name: "maxFeePerGas" },
            { type: "bytes", name: "paymasterAndData" },
            { type: "uint48", name: "validAfter" },
            { type: "uint48", name: "validUntil" },
            { type: "address", name: "entryPoint" },
        ],
    } as const

    let initCode = "0x";
    if (useroperation.factory != null) {
        initCode = useroperation.factory;
        if (useroperation.factoryData != null) {
            initCode += useroperation.factoryData.slice(2);
        }
    }

    let paymasterAndData = "0x";
    if (useroperation.paymaster != null) {
        paymasterAndData = useroperation.paymaster;
        if (useroperation.paymasterVerificationGasLimit != null) {
            paymasterAndData += useroperation.paymasterVerificationGasLimit.toString(16).padStart(32, '0');
        }
        if (useroperation.paymasterPostOpGasLimit != null) {
            paymasterAndData += useroperation.paymasterPostOpGasLimit.toString(16).padStart(32, '0');
        }
        if (useroperation.paymasterData != null) {
            paymasterAndData += useroperation.paymasterData.slice(2);
        }
    }

    const message = {
        safe: useroperation.sender,
        nonce: useroperation.nonce,
        initCode: initCode as `0x${string}`,
        callData: useroperation.callData,
        callGasLimit: useroperation.callGasLimit,
        verificationGasLimit: useroperation.verificationGasLimit,
        preVerificationGas: useroperation.preVerificationGas,
        maxFeePerGas: useroperation.maxFeePerGas,
        maxPriorityFeePerGas: useroperation.maxPriorityFeePerGas,
        paymasterAndData: paymasterAndData as `0x${string}`,
        validAfter: 0,
        validUntil: 0,
        entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032",
    } as const

    return { domain, types, message };
}

export function formatSignature(address: `0x${string}`, signature: string) {
    return SafeAccount.formatEip712SignaturesToUseroperationSignature([address], [signature]);
}
