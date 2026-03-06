import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';

export interface ClipboardItem {
  id: number;
  content_type: string;
  text_value: string | null;
  image_path: string | null;
  thumb_path: string | null;
  hash: string;
  pinned: boolean;
  created_at: number;
  app_source: string | null;
}

export interface LicenseEntitlement {
  tier: string;
  message: string;
  is_unlimited: boolean;
  grace_expires_at: number | null;
}

interface ClipStore {
  items: ClipboardItem[];
  searchQuery: string;
  activeFilter: string;
  selectedId: number | null;
  license: LicenseEntitlement | null;
  isLoading: boolean;

  setSearchQuery: (q: string) => void;
  setActiveFilter: (f: string) => void;
  setSelectedId: (id: number | null) => void;
  fetchHistory: () => Promise<void>;
  pinItem: (id: number) => Promise<void>;
  deleteItem: (id: number) => Promise<void>;
  restoreToClipboard: (id: number) => Promise<void>;
  fetchLicenseStatus: () => Promise<void>;
  activateLicense: (key: string) => Promise<void>;
  deactivateLicense: () => Promise<void>;
  revalidateLicense: () => Promise<LicenseEntitlement>;
  getCheckoutUrl: (cycle: string) => Promise<string>;
  getCustomerPortalUrl: () => Promise<string>;
}

export const useClipStore = create<ClipStore>((set, get) => ({
  items: [],
  searchQuery: '',
  activeFilter: 'all',
  selectedId: null,
  license: null,
  isLoading: false,

  setSearchQuery: (q) => {
    set({ searchQuery: q });
    get().fetchHistory();
  },

  setActiveFilter: (f) => {
    set({ activeFilter: f });
    get().fetchHistory();
  },

  setSelectedId: (id) => set({ selectedId: id }),

  fetchHistory: async () => {
    set({ isLoading: true });
    try {
      const { searchQuery, activeFilter } = get();
      const items = await invoke<ClipboardItem[]>('get_history', {
        search: searchQuery || null,
        contentType: activeFilter === 'all' ? null : activeFilter,
        limit: 100,
        offset: 0,
      });
      set({ items, isLoading: false });
    } catch (e) {
      console.error('Failed to fetch history:', e);
      set({ isLoading: false });
    }
  },

  pinItem: async (id) => {
    try {
      await invoke('pin_item', { id });
      get().fetchHistory();
    } catch (e) {
      console.error('Failed to pin item:', e);
    }
  },

  deleteItem: async (id) => {
    try {
      await invoke('delete_item', { id });
      get().fetchHistory();
    } catch (e) {
      console.error('Failed to delete item:', e);
    }
  },

  restoreToClipboard: async (id) => {
    try {
      await invoke('restore_to_clipboard', { id });
    } catch (e) {
      console.error('Failed to restore to clipboard:', e);
    }
  },

  fetchLicenseStatus: async () => {
    try {
      const license = await invoke<LicenseEntitlement>('get_license_status');
      set({ license });
    } catch (e) {
      console.error('Failed to fetch license status:', e);
    }
  },

  activateLicense: async (key) => {
    await invoke('activate_license', { key });
    await get().fetchLicenseStatus();
    await get().fetchHistory();
  },

  deactivateLicense: async () => {
    await invoke('deactivate_license');
    await get().fetchLicenseStatus();
    await get().fetchHistory();
  },

  revalidateLicense: async () => {
    const result = await invoke<LicenseEntitlement>('revalidate_license');
    set({ license: result });
    return result;
  },

  getCheckoutUrl: async (cycle) => {
    return invoke<string>('get_checkout_url', { cycle });
  },

  getCustomerPortalUrl: async () => {
    return invoke<string>('get_customer_portal_url');
  },
}));
