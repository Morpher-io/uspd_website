import Link from "next/link";
import { Shield } from "lucide-react";

export const Footer = () => {
  return (
    <div className="flex flex-col gap-4 min-w-max container">
      <div className="flex justify-center">
        <p className="">© Permissionless Technologies {new Date().getFullYear()}</p>
      </div>
      
      <div className="flex flex-col md:flex-row justify-center items-center gap-3 font-semibold text-sm md:text-base">
        <Link href="https://docsend.com/view/ifeip6bksazscjf8" target="_blank">Deck</Link>
        <Link href="https://docsend.com/view/8w2gispsuwcjqx6f" target="_blank">Risk Analysis</Link>
        <Link href="https://docsend.com/view/tdqrj9us6hp7dn2b" target="_blank">Litepaper</Link>
        <Link href="https://t.me/+V9hBnsllQVY5YWU0" target="_blank">Join Telegram</Link>
        <Link href="/brand-guidelines">Brand Guidelines</Link>
        <Link href="/documents/uspd_audit_resonance.pdf" target="_blank" className="flex items-center gap-1">
          <Shield size={16} />
          Resonance Audit
        </Link>
        <Link href="/documents/uspd_audit_nethermind.pdf" target="_blank" className="flex items-center gap-1">
          <Shield size={16} />
          Nethermind Audit
        </Link>
      </div>
    </div>
  );
};

