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
  // polygon,
  sepolia,
  // baseSepolia,
  type Chain,
} from 'wagmi/chains';
import {
  QueryClientProvider,
  QueryClient,
} from "@tanstack/react-query";


// Determine which chains to use based on environment
const chains: [Chain, ...Chain[]] = [mainnet, sepolia];

const config = getDefaultConfig({
  appName: 'My RainbowKit App',
  projectId: 'e9dc12eac6024de7f39dcec33cdc30cf',
  chains: chains,
  ssr: true, // If your dApp uses server side rendering (SSR),
  transports: {
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
