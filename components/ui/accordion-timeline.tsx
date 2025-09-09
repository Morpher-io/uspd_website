"use client";
import React, { useState } from "react";
import { ChevronDown } from "lucide-react";

interface TimelineEntry {
  title: string;
  content: React.ReactNode;
}

export const AccordionTimeline = ({ data }: { data: TimelineEntry[] }) => {
  const [openIndex, setOpenIndex] = useState<number | null>(0); // Start with first item open

  const toggleAccordion = (index: number) => {
    setOpenIndex(openIndex === index ? null : index);
  };

  return (
    <div className="w-full space-y-4">
      {data.map((item, index) => (
        <div
          key={index}
          className="border border-border rounded-lg overflow-hidden bg-card"
        >
          <button
            onClick={() => toggleAccordion(index)}
            className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-muted/50 transition-colors"
          >
            <h3 className="text-lg font-semibold text-foreground">
              {item.title}
            </h3>
            <ChevronDown
              className={`h-5 w-5 text-muted-foreground transition-transform duration-200 ${
                openIndex === index ? "rotate-180" : ""
              }`}
            />
          </button>
          {openIndex === index && (
            <div className="px-6 pb-6 border-t border-border">
              <div className="pt-4">
                {item.content}
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
};
