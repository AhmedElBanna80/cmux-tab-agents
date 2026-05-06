import fs from 'fs';

export interface MarkdownReport {
  headers: number;
  code_blocks: number;
  lists: number;
}

export function processMarkdownFile(filePath: string): MarkdownReport {
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }

  const content = fs.readFileSync(filePath, 'utf-8');

  const headers = countHeaders(content);
  const code_blocks = countCodeBlocks(content);
  const lists = countLists(content);

  return {
    headers,
    code_blocks,
    lists
  };
}

function countHeaders(content: string): number {
  const headerRegex = /^#{1,6}\s+/gm;
  const matches = content.match(headerRegex);
  return matches ? matches.length : 0;
}

function countCodeBlocks(content: string): number {
  const codeBlockRegex = /```[\s\S]*?```/g;
  const matches = content.match(codeBlockRegex);
  return matches ? matches.length : 0;
}

function countLists(content: string): number {
  const unorderedListRegex = /^[\s]*[-*+]\s+/gm;
  const orderedListRegex = /^[\s]*\d+\.\s+/gm;

  const unorderedMatches = content.match(unorderedListRegex);
  const orderedMatches = content.match(orderedListRegex);

  const unorderedCount = unorderedMatches ? 1 : 0;
  const orderedCount = orderedMatches ? 1 : 0;

  return unorderedCount + orderedCount;
}
