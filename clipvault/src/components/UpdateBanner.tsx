import { useState, useEffect, useCallback } from 'react';
import { listen } from '@tauri-apps/api/event';
import { check } from '@tauri-apps/plugin-updater';
import { relaunch } from '@tauri-apps/plugin-process';

type UpdateStatus = 'idle' | 'available' | 'downloading' | 'ready' | 'error';

export function UpdateBanner() {
  const [status, setStatus] = useState<UpdateStatus>('idle');
  const [version, setVersion] = useState('');
  const [progress, setProgress] = useState(0);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    const unlisten = listen<string>('update-available', (event) => {
      setVersion(event.payload);
      setStatus('available');
    });
    return () => { unlisten.then((fn) => fn()); };
  }, []);

  const handleUpdate = useCallback(async () => {
    try {
      setStatus('downloading');
      const update = await check();
      if (!update) return;

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
            setStatus('ready');
            break;
        }
      });

      await relaunch();
    } catch (err) {
      console.error('Update failed:', err);
      setStatus('error');
    }
  }, []);

  if (dismissed || status === 'idle') return null;

  return (
    <div className={`update-banner update-banner--${status}`}>
      {status === 'available' && (
        <>
          <span className="update-banner__text">
            v{version} available
          </span>
          <div className="update-banner__actions">
            <button className="update-btn update-btn--primary" onClick={handleUpdate}>
              Update
            </button>
            <button className="update-btn update-btn--ghost" onClick={() => setDismissed(true)}>
              Later
            </button>
          </div>
        </>
      )}

      {status === 'downloading' && (
        <>
          <span className="update-banner__text">Downloading…</span>
          <div className="update-banner__progress-track">
            <div className="update-banner__progress-fill" style={{ width: `${progress}%` }} />
          </div>
          <span className="update-banner__pct">{progress}%</span>
        </>
      )}

      {status === 'ready' && (
        <span className="update-banner__text">Restarting…</span>
      )}

      {status === 'error' && (
        <>
          <span className="update-banner__text">Update failed</span>
          <button className="update-btn update-btn--ghost" onClick={() => setDismissed(true)}>
            Dismiss
          </button>
        </>
      )}
    </div>
  );
}
