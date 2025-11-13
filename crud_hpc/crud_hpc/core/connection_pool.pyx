# cython: language_level=3
# cython: boundscheck=False

"""
High-performance connection pool for SQLite databases.
"""

import sqlite3
import threading
from typing import Optional
cimport cython

cdef class HPCConnectionPool:
    """
    Thread-safe conecction pool with automatic scaling
    """

    cdef:
        list _connections
        int _max_size
        bint _wal_mode
        object _lock
        str _db_path

    def __init__(self, str db_path, int max_size=64, bint wal_mode=True):
        self._db_path = db_path
        self._max_size = max_size
        self._wal_mode = wal_mode
        self._connections = []
        self._lock = threading.Lock()

        # Pre-create connections
        self._initialize_pool()

    def _initialize_pool(self):
        """Initialize connection pool"""
        for _ in range(min(10, self._max_size)): # Start with 10 connections
            conn = self._create_connection()
            self._connections.append(conn)

    cdef object _create_connection(self):
        """Create new optimized connection"""
        conn = sqlite3.connect(self._db_path, check_same_thread=False)

        if self._wal_mode:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.execute("PRAGMA cache_size=64000")
            conn.execute("PRAGMA temp_store=MEMORY")

        conn.row_factory = sqlite3.Row
        return conn
    
    cpdef object get_connection(self):
        """
        Get a connection from the pool, creating a new one if necessary.

        Returns:
            SQLite connection object
        """
        with self._lock:
            if self._connections:
                return self._connections.pop()
            elif len(self._connections) < self._max_size:
                return self._create_connection()
            else:
                # Wait for avaible connection
                while not self._connections:
                    pass
                return self._connections.pop()

    cpdef void release_connection(self, object conn):
        """
        Release connection back to the pool.

        Args:
            conn: SQLite connection object
        """
        with self._lock:
            if len(self._connections) < self._max_size:
                self._connections.append(conn)
            else:
                conn.close()

    cpdef void optimize_connection(self, object conn):
        """
        Optimize an existing connection with performance PRAGMAs.

        Args:
            conn: SQLite connection object
        """
        conn.execute("PRAGMA Optimize)
        conn.commit()

    def close_all(self):
        """
        Close all connections in the pool.
        """
        with self._lock:
            for conn in self._connections:
                conn.close()
            self._connections.clear()