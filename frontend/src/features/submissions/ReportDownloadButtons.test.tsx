import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderWithProviders } from '@/tests/testUtils';
import { ReportDownloadButtons } from './ReportDownloadButtons';
import * as reportsApi from '@api/reports';

jest.mock('@api/reports');
const mockedDownload = reportsApi.downloadReport as jest.MockedFunction<typeof reportsApi.downloadReport>;

describe('ReportDownloadButtons', () => {
  beforeEach(() => {
    mockedDownload.mockResolvedValue(undefined);
  });

  it('renders three format buttons', () => {
    renderWithProviders(<ReportDownloadButtons submissionId={10} />);
    expect(screen.getByTestId('report-download-json')).toBeInTheDocument();
    expect(screen.getByTestId('report-download-md')).toBeInTheDocument();
    expect(screen.getByTestId('report-download-pdf')).toBeInTheDocument();
  });

  it('calls downloadReport with the chosen format', async () => {
    renderWithProviders(<ReportDownloadButtons submissionId={10} />);
    await userEvent.click(screen.getByTestId('report-download-pdf'));
    expect(mockedDownload).toHaveBeenCalledWith(10, 'pdf');
  });

  it('shows an error message when the download fails', async () => {
    mockedDownload.mockRejectedValueOnce(new Error('422'));
    renderWithProviders(<ReportDownloadButtons submissionId={10} />);
    await userEvent.click(screen.getByTestId('report-download-md'));
    expect(await screen.findByTestId('report-download-error')).toBeInTheDocument();
  });
});
