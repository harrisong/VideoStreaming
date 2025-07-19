import React, { createContext, useContext, useState, ReactNode } from 'react';

interface SearchFocusContextType {
  isSearchFocused: boolean;
  setIsSearchFocused: (focused: boolean) => void;
}

const SearchFocusContext = createContext<SearchFocusContextType | undefined>(undefined);

export const SearchFocusProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [isSearchFocused, setIsSearchFocused] = useState(false);

  return (
    <SearchFocusContext.Provider value={{ isSearchFocused, setIsSearchFocused }}>
      {children}
    </SearchFocusContext.Provider>
  );
};

export const useSearchFocus = () => {
  const context = useContext(SearchFocusContext);
  if (context === undefined) {
    throw new Error('useSearchFocus must be used within a SearchFocusProvider');
  }
  return context;
};
