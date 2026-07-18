import { useRef, useState } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { createSubmission, FileSizeLimitError } from '@api/submissions';

const MAX_SIZE_MB = 5;
const MAX_SIZE_BYTES = MAX_SIZE_MB * 1024 * 1024;
const ACCEPTED_EXTENSIONS = '.rb,.py,.js,.ts,.java';

export function NewSubmissionPage() {
  const { id } = useParams<{ id: string }>();
  const projectId = Number(id);
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const fileInputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [fileSizeError, setFileSizeError] = useState<string | null>(null);
  const [mutationError, setMutationError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: (file: File) =>
      createSubmission({ projectId, kind: 'single_file', file }),
    onSuccess: (submission) => {
      queryClient.invalidateQueries({ queryKey: ['submissions', projectId] });
      navigate(`/submissions/${submission.id}`);
    },
    onError: (err) => {
      if (err instanceof FileSizeLimitError) {
        setFileSizeError(err.message);
      } else {
        setMutationError('Upload failed. Please try again.');
      }
    },
  });

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFileSizeError(null);
    setMutationError(null);
    const file = e.target.files?.[0] ?? null;
    if (file && file.size > MAX_SIZE_BYTES) {
      setFileSizeError(`File is ${(file.size / 1024 / 1024).toFixed(1)} MB — limit is ${MAX_SIZE_MB} MB.`);
      setSelectedFile(null);
      return;
    }
    setSelectedFile(file);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedFile) return;
    setMutationError(null);
    mutation.mutate(selectedFile);
  };

  return (
    <div className="max-w-2xl" data-testid="new-submission-page">
      <Link
        to={`/projects/${projectId}`}
        className="mb-5 inline-block text-sm font-medium text-zinc-500 hover:text-zinc-900"
      >
        &larr; Back to project
      </Link>
      <p className="app-kicker">New review</p><h1 className="app-page-title mt-1 mb-2">Submit code</h1><p className="mb-7 text-sm text-zinc-500">Upload one source file for automated analysis.</p>

      <div className="app-panel p-6 sm:p-8">
        <form onSubmit={handleSubmit} noValidate data-testid="submission-form">
          <div className="mb-6">
            <label className="field-label">
              Source file <span className="text-red-500">*</span>
            </label>
            <input
              ref={fileInputRef}
              type="file"
              accept={ACCEPTED_EXTENSIONS}
              onChange={handleFileChange}
              className="block w-full rounded-lg border border-dashed border-zinc-300 bg-zinc-50 p-3 text-sm text-zinc-500 file:mr-4 file:rounded-md file:border-0 file:bg-zinc-900 file:px-3 file:py-2 file:text-sm file:font-medium file:text-white hover:file:bg-zinc-800"
              data-testid="submission-file-input"
            />
            <p className="text-xs text-gray-400 mt-1">
              Accepted: {ACCEPTED_EXTENSIONS} &middot; Max {MAX_SIZE_MB} MB
            </p>
            {fileSizeError && (
              <p className="text-red-600 text-sm mt-1" data-testid="submission-size-error">
                {fileSizeError}
              </p>
            )}
          </div>

          {selectedFile && (
            <div className="mb-5 rounded-lg border border-blue-100 bg-blue-50 px-3 py-2.5 text-sm text-blue-800" data-testid="submission-selected-file">
              Selected: <strong>{selectedFile.name}</strong> (
              {(selectedFile.size / 1024).toFixed(1)} KB)
            </div>
          )}

          {mutationError && (
            <p className="text-red-600 text-sm mb-4" data-testid="submission-error">
              {mutationError}
            </p>
          )}

          <div className="flex gap-3">
            <button
              type="submit"
              disabled={!selectedFile || mutation.isPending}
              className="btn-primary"
              data-testid="submission-submit"
            >
              {mutation.isPending ? 'Uploading...' : 'Submit for review'}
            </button>
            <button
              type="button"
              onClick={() => navigate(`/projects/${projectId}`)}
              className="btn-secondary"
              data-testid="submission-cancel"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
