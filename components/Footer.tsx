import Link from "next/link";
import { Shield, MessageCircle } from "lucide-react";

export const Footer = () => {
  return (
    <div className="container">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 items-start">
        {/* Left Column - Company */}
        <div className="text-center md:text-left">
          <p className="font-semibold">© Permissionless Technologies {new Date().getFullYear()}</p>
          <Link href="https://discord.gg/uspd" target="_blank" className="flex items-center justify-center md:justify-start gap-1 mt-3 font-semibold">
            <MessageCircle size={16} />
            Join Discord
          </Link>
          <Link href="https://x.com/USPD_io" target="_blank" className="flex items-center justify-center md:justify-start gap-1 mt-3 font-semibold">
            <MessageCircle size={16} />
            Follow us on X
          </Link>
        </div>
        
        {/* Center Column - Main Links */}
        <div className="flex flex-col items-center gap-3 font-semibold">
          <Link href="https://docsend.com/view/ifeip6bksazscjf8" target="_blank">Deck</Link>
          <Link href="https://docsend.com/view/8w2gispsuwcjqx6f" target="_blank">Risk Analysis</Link>
          <Link href="https://docsend.com/view/tdqrj9us6hp7dn2b" target="_blank">Litepaper</Link>
        </div>
        
        {/* Right Column - Audits & Brand */}
        <div className="flex flex-col items-center md:items-end gap-3 font-semibold">
          <Link href="/docs/uspd/audit" className="flex items-center gap-1">
            <Shield size={16} />
            Security Audits
          </Link>
          <Link href="/brand-guidelines">Brand Guidelines</Link>
        </div>
      </div>
    </div>
  );
};

