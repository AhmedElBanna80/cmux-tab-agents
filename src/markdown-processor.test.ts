import { describe, it, expect } from 'vitest';
import { processMarkdownFile } from './markdown-processor';
import fs from 'fs';
import path from 'path';
import { tmpdir } from 'os';

describe('Markdown File Processor', () => {
  it('counts headers correctly', () => {
    const tempFile = path.join(tmpdir(), 'test-headers.md');
    fs.writeFileSync(tempFile, '# Header\n## Subheader\n### Sub-subheader\n');

    const result = processMarkdownFile(tempFile);

    expect(result.headers).toBe(3);
    fs.unlinkSync(tempFile);
  });

  it('counts code blocks correctly', () => {
    const tempFile = path.join(tmpdir(), 'test-code.md');
    fs.writeFileSync(tempFile, '```js\nconst x = 1;\n```\n```python\nprint("hello")\n```\n');

    const result = processMarkdownFile(tempFile);

    expect(result.code_blocks).toBe(2);
    fs.unlinkSync(tempFile);
  });

  it('counts lists correctly', () => {
    const tempFile = path.join(tmpdir(), 'test-lists.md');
    fs.writeFileSync(tempFile, '- Item 1\n- Item 2\n\n1. First\n2. Second\n');

    const result = processMarkdownFile(tempFile);

    expect(result.lists).toBe(2);
    fs.unlinkSync(tempFile);
  });

  it('processes complete markdown file', () => {
    const tempFile = path.join(tmpdir(), 'test-complete.md');
    const content = '# Header\n## Subheader\n```js\ncode\n```\n- Item\n';
    fs.writeFileSync(tempFile, content);

    const result = processMarkdownFile(tempFile);

    expect(result).toEqual({
      headers: 2,
      code_blocks: 1,
      lists: 1
    });
    fs.unlinkSync(tempFile);
  });

  it('handles empty files', () => {
    const tempFile = path.join(tmpdir(), 'test-empty.md');
    fs.writeFileSync(tempFile, '');

    const result = processMarkdownFile(tempFile);

    expect(result).toEqual({
      headers: 0,
      code_blocks: 0,
      lists: 0
    });
    fs.unlinkSync(tempFile);
  });

  it('throws helpful error for missing files', () => {
    expect(() => {
      processMarkdownFile('/nonexistent/file.md');
    }).toThrow(/File not found.*nonexistent.*file\.md/);
  });

  it('handles files with no matching elements', () => {
    const tempFile = path.join(tmpdir(), 'test-plain.md');
    fs.writeFileSync(tempFile, 'Just plain text\nNo special elements\n');

    const result = processMarkdownFile(tempFile);

    expect(result).toEqual({
      headers: 0,
      code_blocks: 0,
      lists: 0
    });
    fs.unlinkSync(tempFile);
  });
});
