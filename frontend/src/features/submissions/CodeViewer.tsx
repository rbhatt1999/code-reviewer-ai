import type { Issue } from '@api/schemas';

const SEVERITY_COLORS: Record<string, string> = {
  info: 'text-gray-500 bg-gray-100',
  low: 'text-blue-600 bg-blue-50',
  medium: 'text-yellow-700 bg-yellow-50',
  high: 'text-orange-700 bg-orange-50',
  critical: 'text-red-700 bg-red-100',
};

interface CodeViewerProps {
  content: string;
  issues: Issue[];
}

export function CodeViewer({ content, issues }: CodeViewerProps) {
  const lines = content.split('\n');
  const byLine = new Map<number, Issue[]>();
  for (const issue of issues) {
    const arr = byLine.get(issue.line_start) ?? [];
    arr.push(issue);
    byLine.set(issue.line_start, arr);
  }
  return (
    <pre className="text-sm font-mono overflow-x-auto bg-white border rounded">
      {lines.map((line, i) => {
        const lineNo = i + 1;
        const lineIssues = byLine.get(lineNo) ?? [];
        return (
          <div key={lineNo}>
            <div className="flex" data-testid={`code-line-${lineNo}`}>
              <span className="select-none w-12 pr-3 text-right text-gray-400">{lineNo}</span>
              <span className="whitespace-pre">{line || ' '}</span>
            </div>
            {lineIssues.map((issue) => (
              <div
                key={issue.id}
                data-testid={`issue-overlay-${issue.id}`}
                className={`ml-12 my-1 px-2 py-1 rounded text-xs ${SEVERITY_COLORS[issue.severity] ?? 'bg-gray-100'}`}
              >
                <span className="font-semibold">{issue.rule_id}</span>: {issue.message}
                {issue.suggestion ? <div className="mt-0.5 italic">{issue.suggestion}</div> : null}
              </div>
            ))}
          </div>
        );
      })}
    </pre>
  );
}
