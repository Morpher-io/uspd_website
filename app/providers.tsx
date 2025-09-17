'use client';

import * as React from 'react';
import '@rainbow-me/rainbowkit/styles.css';

import {
  getDefaultConfig,
  RainbowKitProvider,
} from '@rainbow-me/rainbowkit';
import { http, WagmiProvider } from 'wagmi';
import {
  mainnet,
  polygon,
  sepolia,
  base,
  optimism,
  arbitrum,
  avalanche,
  bsc,
  // baseSepolia,
  type Chain,
} from 'wagmi/chains';
import {
  QueryClientProvider,
  QueryClient,
} from "@tanstack/react-query";


// Determine which chains to use based on environment
const isProduction = process.env.NEXT_PUBLIC_LIQUIDITY_CHAINID === '1';

const chains: [Chain, ...Chain[]] = isProduction 
  ? [mainnet, base, polygon, optimism, arbitrum, avalanche, bsc, sepolia]
  : [mainnet, sepolia];

const config = getDefaultConfig({
  appName: 'USPD - US Permissionless Dollar',
  projectId: 'e9dc12eac6024de7f39dcec33cdc30cf',
  chains: chains,
  ssr: true, // If your dApp uses server side rendering (SSR),
  transports: isProduction ? {
    [mainnet.id]: http('https://mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [base.id]: http('https://base-mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [polygon.id]: http('https://polygon-mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [optimism.id]: http('https://optimism-mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [arbitrum.id]: http('https://arbitrum-mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [avalanche.id]: http('https://avalanche-mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [bsc.id]: http('https://bsc-mainnet.infura.io/v3/f33699f28a4b4afe8a75dcaf101a50c8'),
    [sepolia.id]: http('https://sepolia.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169')
  } : {
    [mainnet.id]: http('https://mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [sepolia.id]: http('https://sepolia.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169')
  }
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
