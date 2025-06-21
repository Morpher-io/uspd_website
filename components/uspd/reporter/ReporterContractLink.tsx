'use client'

import { ContractLoader } from '@/components/uspd/common/ContractLoader'
import { Skeleton } from '@/components/ui/skeleton'
import { Button } from '@/components/ui/button'
import { ExternalLink } from 'lucide-react'

const liquidityChainId = Number(process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID) || 11155111;
const isMainnet = liquidityChainId === 1;
const etherscanBaseUrl = isMainnet ? 'https://etherscan.io' : 'https://sepolia.etherscan.io';

export function ReporterContractLink() {
    return (
        <ContractLoader contractKeys={["reporter"]} chainId={liquidityChainId}>
            {(loadedAddresses) => {
                const reporterAddress = loadedAddresses["reporter"];

                if (!reporterAddress) {
                    return <Skeleton className="h-10 w-full max-w-xs" />;
                }

                const reporterUrl = `${etherscanBaseUrl}/address/${reporterAddress}`;

                return (
                    <>
                        <p>
                            The core of this transparency is the <code>OvercollateralizationReporter</code> smart contract. You can inspect its state and verify the system&apos;s health directly on Etherscan.
                        </p>
                        <Button asChild variant="outline" className="mt-4">
                            <a href={reporterUrl} target="_blank" rel="noopener noreferrer">
                                View Contract on Etherscan
                                <ExternalLink className="ml-2 h-4 w-4" />
                            </a>
                        </Button>
                    </>
                );
            }}
        </ContractLoader>
    );
}
