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
  ? [mainnet, base, polygon, optimism, arbitrum, avalanche, bsc]
  : [sepolia, baseSepolia];

const config = getDefaultConfig({
  appName: 'USPD - US Permissionless Dollar',
  projectId: 'e9dc12eac6024de7f39dcec33cdc30cf',
  chains: chains,
  ssr: true, // If your dApp uses server side rendering (SSR),
  transports: isProduction ? {
    [mainnet.id]: http('https://mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [base.id]: http('https://base-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [polygon.id]: http('https://polygon-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [optimism.id]: http('https://optimism-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [arbitrum.id]: http('https://arbitrum-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [avalanche.id]: http('https://avalanche-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [bsc.id]: http('https://bsc-mainnet.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959')
  } : {
    [sepolia.id]: http('https://sepolia.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959'),
    [baseSepolia.id]: http('https://base-sepolia.infura.io/v3/08158a54c7d44a20b4a2a26ad942a959')
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
