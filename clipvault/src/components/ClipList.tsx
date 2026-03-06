import { useClipStore } from '../store/clipStore';
import { ItemCard } from './ItemCard';

export function ClipList() {
  const { items, isLoading } = useClipStore();

  if (isLoading) {
    return (
      <div className="clip-list-empty">
        <div className="spinner" />
        <p>Loading...</p>
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <div className="clip-list-empty">
        <div className="empty-icon">📋</div>
        <h3>No clipboard items yet</h3>
        <p>Copy something to see it appear here</p>
      </div>
    );
  }

  return (
    <div className="clip-list">
      {items.map((item) => (
        <ItemCard key={item.id} item={item} />
      ))}
    </div>
  );
}
