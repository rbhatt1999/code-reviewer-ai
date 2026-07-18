import { useEffect, useState } from 'react';
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

// Returns the most recent live broadcast for this submission (status,
// progress %, and a human-readable "what's happening right now" message),
// in addition to invalidating the React Query cache so persisted fields
// (status, issues_count, etc.) get refetched from the API.
export function useSubmissionChannel(
  submissionId: number | undefined,
): SubmissionStatusEvent | null {
  const queryClient = useQueryClient();
  const [live, setLive] = useState<SubmissionStatusEvent | null>(null);

  useEffect(() => {
    if (!submissionId || Number.isNaN(submissionId)) return;
    const consumer = getConsumer();
    if (!consumer) return;

    const sub = consumer.subscriptions.create<SubmissionStatusEvent>(
      { channel: 'SubmissionChannel', submission_id: submissionId },
      {
        received(data) {
          setLive(data);
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

  return live;
}
