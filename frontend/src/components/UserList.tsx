import React, { useState, useEffect } from 'react';

const UserList: React.FC = () => {
  const [users, setUsers] = useState<any[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const response = await fetch('http://localhost:5050/api/auth/users', {
          credentials: 'include'
        });
        if (response.ok) {
          const data = await response.json();
          setUsers(data);
        } else {
          setError('Failed to fetch user list');
        }
      } catch (error) {
        setError('Error fetching users: ' + (error instanceof Error ? error.message : String(error)));
      }
    };

    fetchUsers();
  }, []);

  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <h2 className="text-center text-3xl font-extrabold text-gray-900">Registered Users</h2>
        {error && <div className="text-red-500 text-center">{error}</div>}
        <div className="border rounded-md overflow-y-auto h-96 p-2 bg-gray-50">
          {users.length > 0 ? (
            users.map(user => (
              <div key={user.id} className="mb-2 p-2 border-b border-gray-200">
                <p className="text-gray-800 text-sm">ID: {user.id}</p>
                <p className="text-gray-800 text-sm">Username: {user.username}</p>
                <p className="text-gray-800 text-sm">Email: {user.email}</p>
              </div>
            ))
          ) : (
            <p className="text-center text-gray-500">No users found.</p>
          )}
        </div>
      </div>
    </div>
  );
};

export default UserList;
