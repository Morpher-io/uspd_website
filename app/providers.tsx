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
  polygon
} from 'wagmi/chains';
import {
  QueryClientProvider,
  QueryClient,
} from "@tanstack/react-query";

const config = getDefaultConfig({
  appName: 'My RainbowKit App',
  projectId: 'YOUR_PROJECT_ID',
  chains: [mainnet, polygon],
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