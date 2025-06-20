import Link from "next/link";

export const Footer = () => {
  return (
    <div className="flex justify-between min-w-max container">

          <div>
            <p className="">© Permissionless Technologies {new Date().getFullYear()}</p>
          </div>
          <div className="flex flex-col md:flex-row gap-3 font-semibold">
            <Link href="https://docsend.com/view/ifeip6bksazscjf8" target="_blank" >Deck</Link>
            <Link href="https://docsend.com/view/8w2gispsuwcjqx6f" target="_blank" >Risk Analysis</Link>
            <Link href="https://docsend.com/view/tdqrj9us6hp7dn2b" target="_blank" >Litepaper</Link>
            <Link href="https://t.me/+V9hBnsllQVY5YWU0" target="_blank">Join Telegram</Link>
          </div>

      </div>
  );
};

