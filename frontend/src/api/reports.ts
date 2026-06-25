import client from './client';

type ReportFormat = 'json' | 'md' | 'pdf';

const MIME: Record<ReportFormat, string> = {
  json: 'application/json',
  md: 'text/markdown',
  pdf: 'application/pdf',
};

export async function downloadReport(submissionId: number, format: ReportFormat): Promise<void> {
  const response = await client.get(`/submissions/${submissionId}/report.${format}`, {
    responseType: 'blob',
  });
  const blob = new Blob([response.data], { type: MIME[format] });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `review-${submissionId}.${format}`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
