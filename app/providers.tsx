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
  baseSepolia,
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
  : [sepolia, baseSepolia];

const config = getDefaultConfig({
  appName: 'USPD - US Permissionless Dollar',
  projectId: 'e9dc12eac6024de7f39dcec33cdc30cf',
  chains: chains,
  ssr: true, // If your dApp uses server side rendering (SSR),
  transports: isProduction ? {
    [mainnet.id]: http('https://mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [base.id]: http('https://base-mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [polygon.id]: http('https://polygon-mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [optimism.id]: http('https://optimism-mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [arbitrum.id]: http('https://arbitrum-mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [avalanche.id]: http('https://avalanche-mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [bsc.id]: http('https://bsc-mainnet.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [sepolia.id]: http('https://sepolia.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169')
  } : {
    [sepolia.id]: http('https://sepolia.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169'),
    [baseSepolia.id]: http('https://base-sepolia.infura.io/v3/e0d5f0b61d16435bb6d7b40471d0a169')
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
