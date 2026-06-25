import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getConsumer } from '@cable/consumer';

interface SubmissionStatusEvent {
  submission_id: number;
  status: string;
  progress?: number;
  issues_count?: number;
  mode?: string | null;
  message?: string | null;
  updated_at?: string;
}

export function useSubmissionChannel(submissionId: number | undefined): void {
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!submissionId || Number.isNaN(submissionId)) return;
    const consumer = getConsumer();
    if (!consumer) return;

    const sub = consumer.subscriptions.create<SubmissionStatusEvent>(
      { channel: 'SubmissionChannel', submission_id: submissionId },
      {
        received(data) {
          queryClient.invalidateQueries({ queryKey: ['submission', submissionId] });
          if (data.status === 'completed') {
            queryClient.invalidateQueries({ queryKey: ['issues', submissionId] });
            queryClient.invalidateQueries({ queryKey: ['review', submissionId] });
            queryClient.invalidateQueries({ queryKey: ['sourceFiles', submissionId] });
          }
        },
      },
    );

    return () => sub.unsubscribe();
  }, [submissionId, queryClient]);
}
