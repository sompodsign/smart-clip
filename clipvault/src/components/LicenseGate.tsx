import { useState } from 'react';
import { useClipStore } from '../store/clipStore';
import { invoke } from '@tauri-apps/api/core';

export function LicenseGate() {
  const { license, activateLicense, deactivateLicense, revalidateLicense, getCheckoutUrl, getCustomerPortalUrl } = useClipStore();
  const [showActivation, setShowActivation] = useState(false);
  const [licenseKey, setLicenseKey] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const isPro = license?.is_unlimited ?? false;

  const handleActivate = async () => {
    if (!licenseKey.trim()) return;
    setLoading(true);
    setError('');
    try {
      await activateLicense(licenseKey.trim());
      setShowActivation(false);
      setLicenseKey('');
    } catch (e: any) {
      setError(typeof e === 'string' ? e : e.message || 'Activation failed.');
    } finally {
      setLoading(false);
    }
  };

  const handleDeactivate = async () => {
    if (!confirm('Deactivate your license? You will lose Pro features.')) return;
    try {
      await deactivateLicense();
    } catch (e: any) {
      console.error('Deactivation error:', e);
    }
  };

  const handleRevalidate = async () => {
    setLoading(true);
    try {
      const result = await revalidateLicense();
      alert(`License check: ${result.message}`);
    } catch (e: any) {
      alert(`License check failed: ${typeof e === 'string' ? e : e.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleManageSubscription = async () => {
    try {
      const url = await getCustomerPortalUrl();
      await invoke('plugin:opener|open_url', { url });
    } catch (e: any) {
      console.error('Failed to open customer portal:', e);
    }
  };

  const handleCheckout = async (cycle: string) => {
    try {
      const url = await getCheckoutUrl(cycle);
      await invoke('plugin:opener|open_url', { url });
    } catch (e: any) {
      alert('Checkout URL not configured.');
    }
  };

  if (isPro) {
    return (
      <div className="license-section pro">
        <div className="license-badge">
          <span className="badge-icon">●</span>
          <span className="badge-text">{license?.message}</span>
        </div>
        <div className="license-actions-row">
          <button className="license-btn subtle" onClick={handleManageSubscription}>
            Manage
          </button>
          <button className="license-btn subtle" onClick={handleRevalidate} disabled={loading}>
            Revalidate
          </button>
          <button className="license-btn danger" onClick={handleDeactivate}>
            Deactivate
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="license-section free">
      <div className="license-badge">
        <span className="badge-icon">○</span>
        <span className="badge-text">{license?.message || 'Free tier (5 items)'}</span>
      </div>

      {!showActivation ? (
        <div className="license-actions">
          <button className="license-btn primary" onClick={() => handleCheckout('monthly')}>
            Monthly
          </button>
          <button className="license-btn primary highlight" onClick={() => handleCheckout('yearly')}>
            Yearly (Best value)
          </button>
          <button className="license-btn ghost" onClick={() => setShowActivation(true)}>
            Activate Key
          </button>
        </div>
      ) : (
        <div className="activation-form">
          <input
            type="text"
            placeholder="Enter license key..."
            value={licenseKey}
            onChange={(e) => setLicenseKey(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleActivate()}
            autoFocus
          />
          {error && <p className="activation-error">{error}</p>}
          <div className="activation-btns">
            <button className="license-btn primary" onClick={handleActivate} disabled={loading}>
              {loading ? 'Activating...' : 'Activate'}
            </button>
            <button className="license-btn ghost" onClick={() => { setShowActivation(false); setError(''); }}>
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
