import { MetadataRoute } from "next";
import {
  Folder,
  MdxFile,
  MetaJsonFile,
  PageMapItem,
} from "nextra";
import { getPageMap } from "nextra/page-map";
import { URL } from "url";

export const dynamic = "force-static";

interface PageType {
  title: string;
  type?: "page";
  display?: "hidden" | "normal" | string;
}

interface SitemapEntry {
  url: string;
  lastModified: string;
}

export function isPageType(value: unknown): value is PageType {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const candidate = value as Record<string, unknown>;
  if ("title" in candidate) {
    if ("type" in candidate && candidate.type !== "page") {
      return false;
    }

    return true;
  }

  return false;
}

const isMetaJSONFile = (value: unknown): value is MetaJsonFile =>
  typeof value === "object" && value !== null && "data" in value;

const isFolder = (value: unknown): value is Folder =>
  typeof value === "object" &&
  value !== null &&
  "name" in value &&
  "route" in value &&
  "children" in value;

const isMDXFile = (value: unknown): value is MdxFile =>
  typeof value === "object" &&
  value !== null &&
  "name" in value &&
  "route" in value &&
  "frontMatter" in value;

// Filter out hidden pages

const parsePageMapItems = (items: PageMapItem[]): SitemapEntry[] => {
  const sitemapEntries: SitemapEntry[] = [];
  
  // Find metadata file to check for hidden pages
  const metaFile = items.find((item) => isMetaJSONFile(item));
  const metadata = Object.entries(metaFile?.data ?? {});
  
  for (const item of items) {
    if (isMetaJSONFile(item)) {
      // Skip metadata files
      continue;
    }
    
    if (isMDXFile(item)) {
      // Check if this page is hidden in metadata
      const metaEntry = metadata.find(([key, _value]) => key === item.name);
      if (metaEntry && isPageType(metaEntry[1]) && metaEntry[1].display === "hidden") {
        continue;
      }
      
      // Add MDX file to sitemap
      sitemapEntries.push({
        url: item.route,
        lastModified: item.frontMatter?.timestamp 
          ? new Date(item.frontMatter.timestamp).toISOString() 
          : new Date().toISOString(),
      });
    } else if (isFolder(item)) {
      // Check if this folder is hidden in metadata
      const metaEntry = metadata.find(([key, _value]) => key === item.name);
      if (metaEntry && isPageType(metaEntry[1]) && metaEntry[1].display === "hidden") {
        continue;
      }
      
      // Recursively parse folder contents
      const childEntries = parsePageMapItems(item.children);
      sitemapEntries.push(...childEntries);
    }
  }
  
  return sitemapEntries;
};

const sitemap = async (): Promise<MetadataRoute.Sitemap> => {
  const baseUrl = "https://uspd.io";
  const pageMap = await getPageMap();


  return parsePageMapItems(pageMap).map((entry) => ({
    url: new URL(entry.url, baseUrl).toString(),
    lastModified: entry.lastModified,
  }));
};

export default sitemap;
