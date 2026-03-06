import { useClipStore, ClipboardItem } from '../store/clipStore';
import { convertFileSrc } from '@tauri-apps/api/core';

interface ItemCardProps {
  item: ClipboardItem;
}

export function ItemCard({ item }: ItemCardProps) {
  const { pinItem, deleteItem, restoreToClipboard, selectedId, setSelectedId } = useClipStore();
  const isSelected = selectedId === item.id;

  const handleClick = () => {
    restoreToClipboard(item.id);
    setSelectedId(item.id);
    setTimeout(() => setSelectedId(null), 1500);
  };

  const preview = () => {
    if (item.content_type === 'image' && item.thumb_path) {
      return (
        <div className="item-image-preview">
          <img src={convertFileSrc(item.thumb_path)} alt="Clipboard image" />
        </div>
      );
    }
    const text = item.text_value || '';
    return (
      <p className="item-text-preview">
        {text.length > 120 ? text.slice(0, 120) + '…' : text}
      </p>
    );
  };

  return (
    <div
      className={`item-card ${isSelected ? 'copied' : ''} ${item.pinned ? 'pinned' : ''}`}
      onClick={handleClick}
      role="button"
      tabIndex={0}
    >
      <div className="item-actions">
        <button
          className={`action-btn pin-btn ${item.pinned ? 'is-pinned' : ''}`}
          onClick={(e) => { e.stopPropagation(); pinItem(item.id); }}
          title={item.pinned ? 'Unpin' : 'Pin'}
        >
          ✦
        </button>
        <button
          className="action-btn delete-btn"
          onClick={(e) => { e.stopPropagation(); deleteItem(item.id); }}
          title="Delete"
        >
          ✕
        </button>
      </div>
      {preview()}
      {isSelected && <div className="copied-badge">✓ Copied</div>}
    </div>
  );
}
