import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { buildApiUrl, API_CONFIG } from '../config';
import ThemePicker from './ThemePicker';
import Logo from './Logo';

const Navbar: React.FC<{ onWatchPartyToggle?: () => void; isWatchParty?: boolean; onSearch?: (query: string) => void }> = ({ onWatchPartyToggle, isWatchParty, onSearch }) => {
  const navigate = useNavigate();
  const [user, setUser] = useState<any>(null);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [isThemePickerOpen, setIsThemePickerOpen] = useState(false);

  useEffect(() => {
    // Load user data from localStorage if token exists
    const token = localStorage.getItem('token');
    const storedUser = localStorage.getItem('user');
    if (token && storedUser) {
      setUser(JSON.parse(storedUser));
    } else {
      setUser(null);
    }

    // Listen for changes in localStorage to update user state
    const handleStorageChange = () => {
      const updatedToken = localStorage.getItem('token');
      const updatedUser = localStorage.getItem('user');
      if (updatedToken && updatedUser) {
        setUser(JSON.parse(updatedUser));
      } else {
        setUser(null);
      }
    };

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, []);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (onSearch && searchQuery.trim()) {
      onSearch(searchQuery.trim());
    }
  };

  return (
    <header className="navbar-themed shadow">
      <div className="max-w-7xl mx-auto py-4 px-4 sm:px-6 lg:px-8 flex justify-between items-center">
        <button
          onClick={() => navigate('/home')}
          className="bg-transparent border-none cursor-pointer p-1 hover:opacity-80 transition-opacity"
        >
          <Logo />
        </button>
        
        {/* Search Bar */}
        {onSearch && (
          <form onSubmit={handleSearch} className="flex-1 max-w-lg mx-8">
            <div className="relative">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search videos..."
                className="w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
              />
              <button
                type="submit"
                className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </button>
            </div>
          </form>
        )}

        <div className="flex gap-2 items-center">
          {/* Theme Picker Button */}
          <button
            onClick={() => setIsThemePickerOpen(true)}
            className="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md"
            style={{
              backgroundColor: 'var(--theme-accent)',
              color: 'var(--theme-text)'
            }}
            title="Theme Settings"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zM21 5H9a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2z" />
            </svg>
          </button>
          
          {onWatchPartyToggle && (
            <button
              onClick={onWatchPartyToggle}
              className="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white"
              style={{
                backgroundColor: isWatchParty ? '#10b981' : 'var(--theme-primary)'
              }}
            >
              {isWatchParty ? 'In Watch Party' : 'Start Watch Party'}
            </button>
          )}
          <div className="relative">
            {user ? (
              <>
                <button
                  onClick={() => setIsDropdownOpen(!isDropdownOpen)}
                  className="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white"
                  style={{
                    backgroundColor: 'var(--theme-secondary)'
                  }}
                >
                  {user.username}
                  <svg className="ml-2 -mr-1 w-4 h-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
                  </svg>
                </button>
                {isDropdownOpen && (
                  <div className="absolute right-0 mt-2 w-48 rounded-md shadow-lg z-10" style={{
                    backgroundColor: 'var(--theme-surface)',
                    color: 'var(--theme-text)'
                  }}>
                    <div className="px-4 py-2 text-sm border-b" style={{
                      borderColor: 'var(--theme-text-secondary)'
                    }}>
                      <p>Username: {user.username}</p>
                      <p>Email: {user.email}</p>
                    </div>
                    <button
                      onClick={async () => {
                        try {
                          await fetch(buildApiUrl(API_CONFIG.ENDPOINTS.LOGOUT), {
                            method: 'POST',
                            credentials: 'include'
                          });
                          localStorage.removeItem('user');
                          localStorage.removeItem('token');
                          setUser(null);
                          navigate('/login');
                        } catch (error) {
                          console.error('Error during logout:', error);
                        }
                      }}
                      className="w-full text-left px-4 py-2 text-sm hover:opacity-80"
                      style={{
                        color: 'var(--theme-text)'
                      }}
                    >
                      Logout
                    </button>
                  </div>
                )}
              </>
            ) : (
              <button
                onClick={() => navigate('/login')}
                className="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white"
                style={{
                  backgroundColor: 'var(--theme-secondary)'
                }}
              >
                Login
              </button>
            )}
          </div>
        </div>
      </div>
      
      {/* Theme Picker Modal */}
      <ThemePicker 
        isOpen={isThemePickerOpen} 
        onClose={() => setIsThemePickerOpen(false)} 
      />
    </header>
  );
};

export default Navbar;
