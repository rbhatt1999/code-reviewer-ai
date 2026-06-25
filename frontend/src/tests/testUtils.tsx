import { render, type RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import type { ReactNode } from 'react';

function makeQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
        gcTime: 0,
        staleTime: 0,
      },
      mutations: {
        retry: false,
      },
    },
  });
}

interface WrapperOptions {
  initialEntries?: string[];
  // When the component under test uses useParams, provide the route pattern
  routePattern?: string;
}

function Wrapper({
  children,
  initialEntries = ['/'],
  routePattern,
}: WrapperOptions & { children: ReactNode }) {
  const queryClient = makeQueryClient();
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={initialEntries}>
        {routePattern ? (
          <Routes>
            <Route path={routePattern} element={children} />
          </Routes>
        ) : (
          children
        )}
      </MemoryRouter>
    </QueryClientProvider>
  );
}

export function renderWithProviders(
  ui: React.ReactElement,
  options?: Omit<RenderOptions, 'wrapper'> & WrapperOptions
) {
  const { initialEntries, routePattern, ...renderOptions } = options ?? {};
  return render(ui, {
    wrapper: ({ children }) => (
      <Wrapper initialEntries={initialEntries} routePattern={routePattern}>
        {children}
      </Wrapper>
    ),
    ...renderOptions,
  });
}
