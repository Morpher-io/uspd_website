import './components.css'
import './globals.css'
import './morpher-uspd.css'
import './normalize.css'




import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';
import { Inter } from 'next/font/google'
import type { Metadata } from 'next'
import { ThemeProvider } from "./theme-provider";
import { Toaster } from "react-hot-toast";

import { url } from 'inspector';

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'Morpher Oracle',
  description: "Welcome to the new era of blockchain oracles. The Morpher Oracle is the first decentralized, zero latency, ERC-4337 based data oracle protocol.",
  metadataBase: new URL('https://oracle.morpher.com'),
  openGraph: {
    type: "website",
    url: "https://oracle.morpher.com/",
    title: "Morpher Oracle",
    description: "Welcome to the new era of blockchain oracles. The Morpher Oracle is the first decentralized, zero latency, ERC-4337 based data oracle protocol.",
    // images: [{
    //   url: "images/og_uspd.png",
    // }],
    
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
        
        <Toaster position="bottom-center" />

      </body>
    </html>
  )
}
