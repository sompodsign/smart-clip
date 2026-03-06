import { useState, useRef, useEffect } from 'react';
import { useClipStore } from '../store/clipStore';

const FILTERS = [
  { value: 'all', label: 'All' },
  { value: 'text', label: 'Text' },
  { value: 'image', label: 'Images' },
];

export function SearchBar() {
  const { searchQuery, setSearchQuery, activeFilter, setActiveFilter } = useClipStore();
  const [localQuery, setLocalQuery] = useState(searchQuery);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    debounceRef.current = setTimeout(() => {
      setSearchQuery(localQuery);
    }, 250);
    return () => clearTimeout(debounceRef.current);
  }, [localQuery, setSearchQuery]);

  return (
    <div className="search-bar">
      <div className="search-input-wrap">
        <svg className="search-icon" viewBox="0 0 20 20" fill="currentColor" width="16" height="16">
          <path fillRule="evenodd" d="M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z" clipRule="evenodd" />
        </svg>
        <input
          id="search-input"
          type="text"
          placeholder="Search clipboard history..."
          value={localQuery}
          onChange={(e) => setLocalQuery(e.target.value)}
          autoFocus
        />
        {localQuery && (
          <button className="clear-btn" onClick={() => { setLocalQuery(''); setSearchQuery(''); }}>
            ×
          </button>
        )}
      </div>
      <div className="filter-pills">
        {FILTERS.map((f) => (
          <button
            key={f.value}
            className={`filter-pill ${activeFilter === f.value ? 'active' : ''}`}
            onClick={() => setActiveFilter(f.value)}
          >
            {f.label}
          </button>
        ))}
      </div>
    </div>
  );
}
