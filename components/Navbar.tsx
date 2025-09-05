'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation';
import { Coins, RedoDot } from 'lucide-react';
export default function CustomNavbar() {
  const pathname = usePathname()

  const navLinks = [
    { href: '/mint-burn-uspd', label: 'Mint/Burn', icon: <Coins  className="w-4 h-4" /> },
    { href: '/bridge', label: 'Bridge', icon: <RedoDot  className="w-4 h-4" /> },
    { href: '/how-it-works', label: 'How USPD works' },
    { href: '/docs/uspd', label: 'Documentation' }
  ]

  return (
    <div className="flex flex-row gap-4 border-l border-border pl-4">
      {navLinks.map(({ href, label, icon }) => (
        <Link
          key={href}
          href={href}
          aria-current={pathname === href ? 'page' : undefined}
          className="flex items-center gap-1 x:focus-visible:nextra-focus x:text-sm x:contrast-more:text-gray-700 x:contrast-more:dark:text-gray-100 x:whitespace-nowrap x:text-gray-600 x:hover:text-gray-800 x:dark:text-gray-400 x:dark:hover:text-gray-200 x:ring-inset x:transition-colors x:aria-[current]:font-medium x:aria-[current]:subpixel-antialiased x:aria-[current]:text-current"
        >
            {icon && (
              <span>
                {icon}
              </span>
            )}
            <span>
            {label}
            </span>
        </Link>
      ))}
    </div>
  )
}
