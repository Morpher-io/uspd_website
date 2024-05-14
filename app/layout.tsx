import './globals.css'

import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';

import type { Metadata } from 'next'
import { Inter } from 'next/font/google'

import { ThemeProvider } from "./theme-provider";

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
      <body className={`${inter.className} bg-slate-50 dark:bg-[#0d1117] duration-200`}>
      <ThemeProvider attribute="class" defaultTheme="dark" enableSystem>
         
          <Providers>{children}</Providers>
        </ThemeProvider>
        
      </body>
    </html>
  )
}
