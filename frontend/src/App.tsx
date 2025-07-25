import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider } from './contexts/ThemeContext';
import { MuiThemeProvider } from './contexts/MuiThemeProvider';
import { SearchFocusProvider } from './contexts/SearchFocusContext';
import Login from './components/Login';
import Register from './components/Register';
import Home from './components/Home';
import VideoPlayer from './components/VideoPlayer';
import UserList from './components/UserList';
import TagVideos from './components/TagVideos';
import Categories from './components/Categories';

function App() {
  // Authentication state can be used for protected routes if needed
  return (
    <ThemeProvider>
      <MuiThemeProvider>
        <SearchFocusProvider>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route 
              path="/home" 
              element={<Home />} 
            />
            <Route 
              path="/video/:id" 
              element={<VideoPlayer />} 
            />
            <Route 
              path="/users" 
              element={<UserList />} 
            />
            <Route 
              path="/tag/:tag" 
              element={<TagVideos />} 
            />
            <Route 
              path="/categories" 
              element={<Categories />} 
            />
            <Route 
              path="/categories/:categoryId" 
              element={<Categories />} 
            />
            <Route path="*" element={<Navigate to="/home" replace />} />
          </Routes>
        </SearchFocusProvider>
      </MuiThemeProvider>
    </ThemeProvider>
  );
}

export default App;
