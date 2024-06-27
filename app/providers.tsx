'use client';

import * as React from 'react';
import {
  RainbowKitProvider,
  getDefaultWallets,
  connectorsForWallets,
  Theme,
  darkTheme 
} from '@rainbow-me/rainbowkit';
import {
  // argentWallet,
  trustWallet,
  ledgerWallet,
  frameWallet,
  injectedWallet,
  metaMaskWallet
} from '@rainbow-me/rainbowkit/wallets';
import { configureChains, createConfig, WagmiConfig } from 'wagmi';
import {
  // mainnet,
  sepolia,
  // optimism,
  // arbitrum,
  // base,
  // zora,
  goerli,
} from 'wagmi/chains';
import { publicProvider } from 'wagmi/providers/public';

const { chains, publicClient, webSocketPublicClient } = configureChains(
  [
    // mainnet,
    sepolia,
    // optimism,
    // arbitrum,
    // base,
    // zora,
    ...(process.env.NEXT_PUBLIC_ENABLE_TESTNETS === 'true' ? [goerli] : []),
  ],
  [publicProvider()]
);

const projectId = '969a61530d45668dc584f51729796388';
const wallets = [metaMaskWallet({chains, projectId}), frameWallet({chains}), injectedWallet({chains}),ledgerWallet({chains,projectId}),trustWallet({chains, projectId})];
const connectors = connectorsForWallets([{groupName: "Connect", wallets}]);


const demoAppInfo = {
  appName: 'USPD Token Demo',
};

// const connectors = connectorsForWallets([
//   ...wallets,
//   {
//     groupName: 'Other',
//     wallets: [
//       argentWallet({ projectId, chains }),
//       trustWallet({ projectId, chains }),
//       ledgerWallet({ projectId, chains }),
//     ],
//   },
// ]);

const wagmiConfig = createConfig({
  autoConnect: true,
  connectors,
  publicClient,
  webSocketPublicClient,
});
let theme = darkTheme({
  accentColor: '#00C386',
  accentColorForeground: '#040126',

  borderRadius: 'small',
  fontStack: 'system',
  overlayBlur: 'small',
  
})

theme.fonts.body = 'Barlow, sans-serif'




export function Providers({ children }: { children: React.ReactNode }) {
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => setMounted(true), []);
  return (
    <WagmiConfig config={wagmiConfig}>
      <RainbowKitProvider chains={chains} appInfo={demoAppInfo} theme={theme} modalSize="compact">
        {mounted && children}
      </RainbowKitProvider>
    </WagmiConfig>
  );
}