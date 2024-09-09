"use client";
import { useState, useEffect } from "react";


export const Footer = () => {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);


  if (!mounted) {
    return null;
  }


  return (
    <div className="footer">
        <div className="footer-container">
          <div>
            <p className="footer-cc">© Permissionless Technologies 2024</p>
          </div>
          <div className="footer-links">
            <a href="https://docsend.com/view/ifeip6bksazscjf8" target="_blank" className="footer-link">Deck</a>
            <a href="https://docsend.com/view/hccjyq4i6th6myk4" target="_blank" className="footer-link">Simulation</a>
            <a href="https://docsend.com/view/8w2gispsuwcjqx6f" target="_blank" className="footer-link">Risk Analysis</a>
            <a href="https://docsend.com/view/tdqrj9us6hp7dn2b" target="_blank" className="footer-link">Litepaper</a>
            <a href="https://t.me/+V9hBnsllQVY5YWU0" target="_blank" className="footer-link">Join Telegram</a>
          </div>
        </div>
      </div>
  );
};