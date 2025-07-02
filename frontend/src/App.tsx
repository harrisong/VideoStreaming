import React from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import Login from './components/Login';
import Register from './components/Register';
import Home from './components/Home';
import VideoPlayer from './components/VideoPlayer';
import UserList from './components/UserList';
import TagVideos from './components/TagVideos';

function App() {
  const isAuthenticated = !!localStorage.getItem('token') && !!localStorage.getItem('user');

  return (
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
      <Route path="*" element={<Navigate to="/home" replace />} />
    </Routes>
  );
}

export default App;
