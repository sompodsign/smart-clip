import { useState, useRef, useEffect, useCallback } from 'react';
import { check } from '@tauri-apps/plugin-updater';
import { relaunch } from '@tauri-apps/plugin-process';
import { useClipStore } from '../store/clipStore';

const ITEM_LIMITS = [20, 50, 100, 200] as const;

type UpdateCheckStatus = 'idle' | 'checking' | 'up-to-date' | 'downloading' | 'error';

export function SettingsMenu() {
  const [open, setOpen] = useState(false);
  const [updateStatus, setUpdateStatus] = useState<UpdateCheckStatus>('idle');
  const [progress, setProgress] = useState(0);
  const menuRef = useRef<HTMLDivElement>(null);
  const { maxItems, setMaxItems } = useClipStore();

  // Close on click outside
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const handleCheckUpdate = useCallback(async () => {
    try {
      setUpdateStatus('checking');
      const update = await check();
      if (!update) {
        setUpdateStatus('up-to-date');
        setTimeout(() => setUpdateStatus('idle'), 2500);
        return;
      }

      setUpdateStatus('downloading');
      let downloaded = 0;
      let total = 0;

      await update.downloadAndInstall((event) => {
        switch (event.event) {
          case 'Started':
            total = event.data.contentLength ?? 0;
            break;
          case 'Progress':
            downloaded += event.data.chunkLength;
            if (total > 0) setProgress(Math.round((downloaded / total) * 100));
            break;
          case 'Finished':
            setProgress(100);
            break;
        }
      });

      await relaunch();
    } catch (err) {
      console.error('Update check failed:', err);
      setUpdateStatus('error');
      setTimeout(() => setUpdateStatus('idle'), 3000);
    }
  }, []);

  return (
    <div className="settings-wrap" ref={menuRef}>
      <button
        className={`settings-btn${open ? ' active' : ''}`}
        onClick={() => setOpen(!open)}
        title="Settings"
      >
        ⚙
      </button>

      {open && (
        <div className="settings-menu">
          <div className="settings-section">
            <span className="settings-label">Max Items</span>
            <div className="settings-options">
              {ITEM_LIMITS.map((n) => (
                <button
                  key={n}
                  className={`settings-option${maxItems === n ? ' active' : ''}`}
                  onClick={() => {
                    setMaxItems(n);
                  }}
                >
                  {n}
                </button>
              ))}
            </div>
          </div>

          <div className="settings-divider" />

          <div className="settings-section">
            <button
              className="settings-action-btn"
              onClick={handleCheckUpdate}
              disabled={updateStatus === 'checking' || updateStatus === 'downloading'}
            >
              {updateStatus === 'idle' && '↻ Check for Update'}
              {updateStatus === 'checking' && '⟳ Checking…'}
              {updateStatus === 'up-to-date' && '✓ Up to date'}
              {updateStatus === 'downloading' && `⬇ Downloading ${progress}%`}
              {updateStatus === 'error' && '✕ Update failed'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
