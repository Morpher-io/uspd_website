

import { Footer as NextraFooter, Layout, Navbar } from 'nextra-theme-docs'
import { Footer } from '@/components/Footer';
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import { Toaster } from "@/components/ui/sonner" // if you re-export from ui                                                      

import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';
import { Inter } from 'next/font/google'
import { Barlow } from 'next/font/google';
import type { Metadata } from 'next'
// import { Toaster } from "react-hot-toast";
import "./globals.css"
import Image from 'next/image'


import UspdLogo from "@/public/images/logo_uspd.svg";

import { ConnectButton } from '@rainbow-me/rainbowkit';



const inter = Inter({ subsets: ['latin'] })
const barlow = Barlow({ subsets: ['latin'], weight: ['100', '200', '300', '400', '500', '600', '700', '800', '900'] })

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

  }

}


const navbar = (
  <Navbar
    logo={<div className='flex gap-2 items-center'><Image className="h-8 w-8" alt="Uspd Logo" src={UspdLogo} /><span>USPD</span></div>}
    children={<ConnectButton label="Connect" showBalance={false} accountStatus={"avatar"} chainStatus={"icon"} />}

  // ... Your additional navbar options
  />
)
const footer = <NextraFooter><Footer /></NextraFooter>

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html // Not required, but good for SEO
      lang="en"
      // Required to be set
      dir="ltr"
      // Suggested by `next-themes` package https://github.com/pacocoursey/next-themes#with-app
      suppressHydrationWarning>
      <Head>
        <link rel="icon" href="/icon?<generated>" type="image/png" sizes="32x32" />
      </Head>
      <body className={`${barlow.className} duration-200`}>
        <Providers>
          <Layout
            navbar={navbar}
            pageMap={await getPageMap()}
            docsRepositoryBase="https://github.com/morpher-io/uspd"
            footer={footer}
          // ... Your additional layout options
          >




            {children}


          </Layout>
        </Providers>

      <Toaster richColors /> 
      </body>
    </html>
  )
}



