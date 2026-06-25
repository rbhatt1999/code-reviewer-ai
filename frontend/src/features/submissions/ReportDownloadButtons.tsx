import { useState } from 'react';
import { downloadReport } from '@api/reports';

type ReportFormat = 'json' | 'md' | 'pdf';

interface Props {
  submissionId: number;
}

export function ReportDownloadButtons({ submissionId }: Props) {
  const [downloading, setDownloading] = useState<ReportFormat | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handle(fmt: ReportFormat) {
    setError(null);
    setDownloading(fmt);
    try {
      await downloadReport(submissionId, fmt);
    } catch {
      setError(`Could not download the ${fmt.toUpperCase()} report.`);
    } finally {
      setDownloading(null);
    }
  }

  const buttonClass =
    'px-3 py-1.5 text-sm font-medium rounded border border-gray-300 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed';

  return (
    <div className="flex items-center gap-2">
      <span className="text-sm text-gray-600 font-medium">Download report:</span>
      {(['json', 'md', 'pdf'] as ReportFormat[]).map((fmt) => (
        <button
          key={fmt}
          type="button"
          className={buttonClass}
          data-testid={`report-download-${fmt}`}
          disabled={downloading !== null}
          onClick={() => handle(fmt)}
        >
          {fmt.toUpperCase()}
        </button>
      ))}
      {error && (
        <p className="text-sm text-red-600" data-testid="report-download-error">
          {error}
        </p>
      )}
    </div>
  );
}
