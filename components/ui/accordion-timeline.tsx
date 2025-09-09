"use client";
import React from "react";

interface TimelineEntry {
  title: string;
  content: React.ReactNode;
}

export const AccordionTimeline = ({ data }: { data: TimelineEntry[] }) => {
  return (
    <div className="w-full space-y-8">
      {data.map((item, index) => (
        <div key={index} className="w-full">
          <div className="sticky top-4 z-10 bg-background/95 backdrop-blur-sm border-b border-border pb-4 mb-6">
            <h3 className="text-2xl font-bold text-foreground">
              {item.title}
            </h3>
          </div>
          <div className="px-4">
            {item.content}
          </div>
        </div>
      ))}
    </div>
  );
};
