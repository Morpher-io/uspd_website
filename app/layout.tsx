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

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'USPD Demo',
  description: 'Demo of the US Permissionless Dollar',
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
      <body className={`${inter.className} bg-slate-50 dark:bg-[#0d1117] duration-200`}>
      <ThemeProvider attribute="class" defaultTheme="dark" enableSystem>
         
          <Providers>{children}</Providers>
        </ThemeProvider>
        <Footer></Footer>
        
      </body>
    </html>
  )
}
