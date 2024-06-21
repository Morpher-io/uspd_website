import './components.css'
import './globals.css'
import './morpher-uspd.css'
import './normalize.css'




import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';
import { Inter } from 'next/font/google'
import type { Metadata } from 'next'
import { ThemeProvider } from "./theme-provider";
import {Footer} from '@/components/Footer';
import { Toaster } from "react-hot-toast";

import { url } from 'inspector';

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'USPD Demo',
  description: "Welcome to the new era of decentralized stablecoins. USPD is the only sovereign stablecoin that doesn&#x27;t rely on banks. It&#x27;s backed by ETH with fully transparent on-chain reserves.",
  metadataBase: new URL('https://uspd.io'),
  openGraph: {
    type: "website",
    url: "https://uspd.io/",
    title: "USPD - Decentralized, Permissionless &amp; Transparent Stablecoin",
    description: "Welcome to the new era of decentralized stablecoins. USPD is the only sovereign stablecoin that doesn&#x27;t rely on banks. It&#x27;s backed by ETH with fully transparent on-chain reserves.",
    images: [{
      url: "images/og_uspd.png",
    }],
    
  },
  viewport: 'width=device-width, initial-scale=1'

}


export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <head>
        <link href="images/favicon.png" rel="shortcut icon" type="image/x-icon" />
        <link href="images/webclip.png" rel="apple-touch-icon" />
      </head>
      <body className={`${inter.className} duration-200`}>
      <ThemeProvider attribute="class" defaultTheme="dark" enableSystem>
         
          <Providers>{children}</Providers>
        </ThemeProvider>
        <Footer></Footer>
        
        <Toaster position="bottom-center" />

      </body>
    </html>
  )
}
