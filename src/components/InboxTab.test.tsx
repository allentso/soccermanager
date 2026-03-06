import { render, screen } from '@testing-library/react';
import InboxTab from './InboxTab';
import { expect, vi, test } from 'vitest';

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation(query => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

vi.mock('react-i18next', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual as any,
    useTranslation: () => ({
      t: (key: string) => key,
      i18n: { language: 'en' }
    })
  };
});

const mockGameState = {
  manager: { team_id: 't1', first_name: 'John', last_name: 'Doe' },
  teams: [],
  messages: [
    { id: 'm1', subject: 'Test Message 1', body: 'Test Body', sender: 'Sender', sender_role: 'Role', date: '2025-01-01', read: false, category: 'System', priority: 'Normal', actions: [], context: {} },
    { id: 'm2', subject: 'Test Message 2', body: 'Test Body', sender: 'Sender', sender_role: 'Role', date: '2025-01-01', read: false, category: 'System', priority: 'Normal', actions: [], context: {} },
    { id: 'm3', subject: 'Test Message 3', body: 'Test Body', sender: 'Sender', sender_role: 'Role', date: '2025-01-01', read: false, category: 'System', priority: 'Normal', actions: [], context: {} }
  ]
};

test('InboxTab renders each message exactly once in the list', () => {
  const { } = render(<InboxTab gameState={mockGameState as any} onGameUpdate={() => {}} />);
  const items = screen.getAllByText(/Test Message \d/);
  console.log('Number of message titles rendered:', items.length);
  expect(items.length).toBe(3);
});
