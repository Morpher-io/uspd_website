'use client';

import * as React from 'react';
import '@rainbow-me/rainbowkit/styles.css';

import {
  darkTheme,
  getDefaultConfig,
  lightTheme,
  RainbowKitProvider,
} from '@rainbow-me/rainbowkit';
import { WagmiConfig, WagmiProvider } from 'wagmi';
import {
  mainnet,
  polygon,
  Chain
} from 'wagmi/chains';
import {
  QueryClientProvider,
  QueryClient,
} from "@tanstack/react-query";

// Define a custom Anvil chain for development
const anvilChain: Chain = {
  id: 112233,
  name: 'Anvil',
  nativeCurrency: {
    decimals: 18,
    name: 'Ethereum',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: { http: ['http://localhost:8545'] },
    public: { http: ['http://localhost:8545'] },
  },
  blockExplorers: {
    default: { name: 'Local Explorer', url: 'http://localhost:8545' },
  },
  testnet: true,
};

// Determine which chains to use based on environment
const chains = process.env.NODE_ENV === 'development' 
  ? [anvilChain, mainnet, polygon]
  : [mainnet, polygon];

const config = getDefaultConfig({
  appName: 'My RainbowKit App',
  projectId: 'YOUR_PROJECT_ID',
  chains: chains,
  ssr: true, // If your dApp uses server side rendering (SSR)
});

const queryClient = new QueryClient();


const demoAppInfo = {
  appName: 'USPD Token Demo',
};



export function Providers({ children }: { children: React.ReactNode }) {
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => setMounted(true), []);
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider children={children} theme={darkTheme()} />
      </QueryClientProvider>
    </WagmiProvider>
  );
}
