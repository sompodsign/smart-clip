import { useEffect } from 'react';
import { listen } from '@tauri-apps/api/event';
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window';
import { useClipStore } from './store/clipStore';
import { SearchBar } from './components/SearchBar';
import { ClipList } from './components/ClipList';
import { LicenseGate } from './components/LicenseGate';
import { UpdateBanner } from './components/UpdateBanner';
import { SettingsMenu } from './components/SettingsMenu';
import './App.css';

const HEADER_H = 40;
const SEARCH_H = 80;
const ITEM_H = 56;
const FOOTER_H = 74;
const LIST_PAD = 8;
const MIN_H = 200;
const MAX_H = 9999;
const PANEL_W = 340;

function App() {
  const { fetchHistory, fetchLicenseStatus, fetchMaxItems, fetchPlainTextOnly, items, license } = useClipStore();

  useEffect(() => {
    fetchHistory();
    fetchLicenseStatus();
    fetchMaxItems();
    fetchPlainTextOnly();

    const unlisten = listen('clipboard-change', () => {
      fetchHistory();
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, [fetchHistory, fetchLicenseStatus, fetchMaxItems, fetchPlainTextOnly]);

  // Dynamically resize window based on item count
  useEffect(() => {
    const count = items.length;
    const contentH = HEADER_H + SEARCH_H + LIST_PAD + (count * ITEM_H) + FOOTER_H;
    const screenH = window.screen.availHeight;
    const targetH = Math.max(MIN_H, Math.min(contentH, screenH - 30, MAX_H));
    getCurrentWindow().setSize(new LogicalSize(PANEL_W, targetH)).catch(() => {});
  }, [items.length]);

  const itemCount = items.length;
  const isPro = license?.is_unlimited ?? false;

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-brand">
          <h1 className="app-title">SmartClip</h1>
        </div>
        <div className="header-right">
          <SettingsMenu />
          <div className="item-counter">
            <span className="counter-num">{itemCount}</span>
            <span className="counter-label">
              {isPro ? ' items' : ' / 5'}
            </span>
          </div>
        </div>
      </header>

      <UpdateBanner />
      <SearchBar />
      <ClipList />

      <footer className="app-footer">
        <LicenseGate />
      </footer>
    </div>
  );
}

export default App;
