import React from 'react';

const Logo: React.FC<{ className?: string }> = ({ className = '' }) => {
  return (
    <svg
      width="140"
      height="32"
      viewBox="0 0 140 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
    >
      <defs>
        {/* Simple gradient for the play button */}
        <linearGradient id="playGradient" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="var(--theme-primary)" />
          <stop offset="100%" stopColor="var(--theme-secondary)" />
        </linearGradient>
      </defs>
      
      {/* Play button icon - similar to YouTube */}
      <g transform="translate(8, 8)">
        <rect
          x="0"
          y="0"
          width="16"
          height="16"
          rx="3"
          fill="url(#playGradient)"
        />
        <polygon
          points="6,5 6,11 11,8"
          fill="white"
        />
      </g>
      
      {/* Text "VibeStream" - clean and simple */}
      <g transform="translate(32, 10)" fill="var(--theme-text)" fontSize="16" fontFamily="system-ui, -apple-system, sans-serif" fontWeight="700">
        <text x="0" y="12">VibeStream</text>
      </g>
    </svg>
  );
};

export default Logo;
