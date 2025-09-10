import { Footer as NextraFooter, Layout, Navbar } from 'nextra-theme-docs'
import { Footer } from '@/components/Footer';
import { Banner, Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import { Toaster } from "@/components/ui/sonner" // if you re-export from ui                                                      

import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';
import { ContractProvider } from '@/components/uspd/common/ContractContext';
import { Barlow } from 'next/font/google';
import type { Metadata } from 'next'
// import { Toaster } from "react-hot-toast";
import "./globals.css"
import Image from 'next/image'


import UspdLogo from "@/public/images/logo_uspd.svg";
import NavbarStats from '@/components/uspd/reporter/NavbarStats';
import CustomNavbar from '@/components/Navbar';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import Script from 'next/script';
import { AnimatedRibbon } from '@/components/ui/animated-ribbon';



const barlow = Barlow({ subsets: ['latin'], weight: ['100', '200', '300', '400', '500', '600', '700', '800', '900'] })

export const metadata: Metadata = {
  title: 'USPD - The Dollar for the Decentralized Nation',
  description: "US Permissionless Dollar is the first fully transparent, decentralized and permissionless stablecoin with native yield and on-chain proof of reserves.",
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
  <div>
    
    <Navbar
      className='font-medium'

      logoLink={false}
      logo={<div className='flex items-center'>
        <Link href="/" className='flex gap-2 items-center border-r border-border pr-4 mr-4'>
          <Image className="h-8 w-8" alt="Uspd Logo" src={UspdLogo} />
          <span>USPD</span>
        </Link>
        <div className='hidden lg:block flex flex-row'>
          <NavbarStats />
          
        </div>
        <div className='hidden md:block'>
          <CustomNavbar />
        </div>
      </div>}
    ><ConnectButton label="Connect" showBalance={false} accountStatus={"avatar"} chainStatus={"icon"} />

    </Navbar><AnimatedRibbon 
      text="We are in Testnet +++ Mainnet Launch Q4 2025 +++ Follow on X, Discord or Telegram to stay up to date"
      className="border-b border-border/20"
    />
  </div>
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
          <ContractProvider>
            <Layout
              navbar={navbar}
              editLink={null}
              feedback={{content: null}}
              pageMap={await getPageMap()}
              docsRepositoryBase="https://github.com/morpher-io/uspd"
              footer={footer}
              nextThemes={{defaultTheme: "dark"}}
            // ... Your additional layout options
            >


              {children}


            </Layout>
          </ContractProvider>
        </Providers>

        <Toaster richColors />

          {/* 100% privacy-first analytics */}
          <Script src="https://scripts.simpleanalyticscdn.com/latest.js" />
      </body>
    </html>
  )
}
