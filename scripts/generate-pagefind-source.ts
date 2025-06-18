#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { glob } from 'glob';
import matter from 'gray-matter';
import { remark } from 'remark';
import remarkHtml from 'remark-html';
// remarkGFM and remarkParse are not used, removed for clarity
// import remarkGFM from 'remark-gfm';
// import remarkParse from 'remark-parse';
// unified is not used directly, removed for clarity
// import { unified } from "unified";

const sourceDir: string = path.join(process.cwd(), 'app');
const targetDir: string = path.join(process.cwd(), 'pagefind-source');
const sourceDirRelative: string = path.relative(process.cwd(), sourceDir);
const targetDirRelative: string = path.relative(process.cwd(), targetDir);

console.log(`Starting MDX to HTML conversion for Pagefind...`);
console.log(`Source directory: ${sourceDirRelative}`);
console.log(`Target directory: ${targetDirRelative}`);

async function processFiles(): Promise<void> {
    // Ensure target directory exists
    if (fs.existsSync(targetDir)) {
        console.log(`Cleaning existing target directory: ${targetDirRelative}`);
        fs.rmSync(targetDir, { recursive: true, force: true });
    }
    fs.mkdirSync(targetDir, { recursive: true });

    // Find all .mdx files in the source directory, ignoring node_modules etc.
    const files: string[] = await glob('**/*.mdx', {
        cwd: sourceDir,
        ignore: ['**/node_modules/**', '**/.*/**'], // Basic ignore patterns
        nodir: true, // Only find files
        absolute: true, // Get absolute paths
    });

    console.log(`Found ${files.length} .mdx files to process.`);

    let processedCount = 0;
    let errorCount: number = 0;

    for (const file of files) {
        try {
            const relativePath: string = path.relative(sourceDir, file);
            console.log(`Processing: ${relativePath}`);

            const fileContent: string = fs.readFileSync(file, 'utf8');

            // 1. Remove Frontmatter
            const { content: contentWithoutFrontmatter } = matter(fileContent);

            // 2. Remove JS/TS imports/exports (simple regex, might need refinement)
            let cleanedContent = contentWithoutFrontmatter
                .replace(/^import\s+.*?\s+from\s+['"].*?['"];?\s*$/gm, '') // Imports
                .replace(/^export\s+(const|let|var|function|default|type|interface)\s+.*?$/gm, '') // Exports
                .replace(/^export\s+\{.*?\};?\s*$/gm, ''); // Named exports

            // 3. Remove JSX tags (attempting to keep inner content)
            // Remove self-closing tags first
            cleanedContent = cleanedContent.replace(/<[A-Z][^>]*?\/>/gs, '');
            // Remove opening tags
            cleanedContent = cleanedContent.replace(/<([A-Z][A-Za-z0-9]*)(?:\s+[^>]*)?>/gs, '');
            // Remove closing tags
            cleanedContent = cleanedContent.replace(/<\/([A-Z][A-Za-z0-9]*)>/gs, '');

            // Trim extra whitespace that might result from removals
            cleanedContent = cleanedContent.trim();

            // 4. Convert the resulting "Markdown" to HTML fragment (only if content exists)
            let htmlFragment: string = '';
            if (cleanedContent) {
                // Use the actual cleaned content here, not "test"
                const processed = await remark().use(remarkHtml).process(cleanedContent);
                htmlFragment = String(processed);
            } else {
                console.log(`Skipping remark processing for ${relativePath} due to empty content after cleaning.`);
            }

            // 5. Wrap in basic HTML structure
            const finalHtml: string = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>${path.basename(file, '.mdx')}</title>
</head>
<body>
    <main data-pagefind-body>
${htmlFragment}
    </main>
</body>
</html>`;

            // 6. Determine output path and write file
            let targetPath: string;
            const parsedRelativePath = path.parse(relativePath); // Parse path components

            // If the original filename was 'page.mdx', output as 'index.html' in its directory
            if (parsedRelativePath.name === 'page') {
              targetPath = path.join(targetDir, parsedRelativePath.dir, 'index.html');
            } else {
              // Otherwise, just replace .mdx with .html
              targetPath = path.join(targetDir, relativePath.replace(/\.mdx$/, '.html'));
            }

            const targetFileDir: string = path.dirname(targetPath);

            // Ensure the directory for the output file exists
            fs.mkdirSync(targetFileDir, { recursive: true });

            fs.writeFileSync(targetPath, finalHtml, 'utf8');
            processedCount++;

        } catch (error: any) { // Use 'any' or 'unknown' for catch block error
            console.error(`Error processing file ${path.relative(sourceDir, file)}:`, error.message || error);
            errorCount++;
        }
    }

    console.log(`\nFinished processing.`);
    console.log(`Successfully processed: ${processedCount} files.`);
    console.log(`Failed to process: ${errorCount} files.`);

    if (errorCount > 0) {
        process.exit(1); // Exit with error code if any file failed
    }
}

processFiles().catch((err: any) => { // Use 'any' or 'unknown'
    console.error("An unexpected error occurred during the script execution:", err.message || err);
    process.exit(1);
});
