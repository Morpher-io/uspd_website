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
    mintUserOp.maxFeePerGas = BigInt('90000000000');

    return mintUserOp;
}

export async function createBurnUserOp(ownerPublicAddress: string, amount: bigint) {

    const smartAccount = SafeAccount.initializeNewAccount([ownerPublicAddress]);

    console.log("Account address (sender): " + smartAccount.accountAddress);

    const burnFunctionSignature = 'burn(uint256,address)';
    const burnFunctionSelector = getFunctionSelector(burnFunctionSignature);

    const burnTransactionCallData = createCallData(
        burnFunctionSelector,
        ["uint256", "address"],
        [amount, smartAccount.accountAddress]
    );
    console.log(burnTransactionCallData)
    const burnTransaction = {
        to: process.env.NEXT_PUBLIC_TOKEN_ADDRESS!,
        value: BigInt("1000000000000000"),
        data: burnTransactionCallData,
    }
    const burnUserOp = await smartAccount.createUserOperation(
        [burnTransaction],
        process.env.NEXT_PUBLIC_ETH_RPC!,
        process.env.NEXT_PUBLIC_BUNDLER_RPC!,
    )

    burnUserOp.verificationGasLimit = BigInt(Math.round(Number(burnUserOp.verificationGasLimit) * 1.2));
    burnUserOp.maxFeePerGas = BigInt('90000000000');

    return burnUserOp;
}
