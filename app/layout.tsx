import { Footer as NextraFooter, Layout, Navbar } from 'nextra-theme-docs'
import { Footer } from '@/components/Footer';
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import { Toaster } from "@/components/ui/sonner" // if you re-export from ui                                                      

import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';
import { Barlow } from 'next/font/google';
import type { Metadata } from 'next'
// import { Toaster } from "react-hot-toast";
import "./globals.css"
import Image from 'next/image'


import UspdLogo from "@/public/images/logo_uspd.svg";
import NavbarStats from '@/components/uspd/reporter/NavbarStats';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import { headers } from "next/headers";



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
    className='font-medium'

    logoLink={false}
    logo={<div className='flex items-center'>
      <Link href="/" className='flex gap-2 items-center'>
        <Image className="h-8 w-8" alt="Uspd Logo" src={UspdLogo} />
        <span>USPD</span>
      </Link>
      <div className='hidden lg:block flex flex-row'>
        <NavbarStats />
        
      </div>
      <div>
        <Link aria-current={(await headers()).get("next-url") == "/uspd" ? true : undefined} className='x:focus-visible:nextra-focus x:text-sm x:contrast-more:text-gray-700 x:contrast-more:dark:text-gray-100 x:whitespace-nowrap x:text-gray-600 x:hover:text-gray-800 x:dark:text-gray-400 x:dark:hover:text-gray-200 x:ring-inset x:transition-colors x:aria-[current]:font-medium x:aria-[current]:subpixel-antialiased x:aria-[current]:text-current' href="/uspd">Mint</Link>
        </div>
    </div>}
  ><ConnectButton label="Connect" showBalance={false} accountStatus={"avatar"} chainStatus={"icon"} />

  </Navbar>
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
            nextThemes={{defaultTheme: "dark"}}
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
