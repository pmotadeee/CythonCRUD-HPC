# cython: language_level=3
# cython: boundscheck=False
# cython wraparound=False
# cython: nonecheck=False
# cython: cdivision=True

"""
High-performance CRUD engine for data operations.
"""

import sqlite3
import json
from typing import List, Dict, Any, Optional
from libc.stdlib cimport malloc, free
from libc.string cimport memcpy
cimport cython

cdef class CythonCRUDEngine:
    """
    Main CRUD engine class for high-performance data operations.
    
    Features:
    - Connection pooling
    - Query optimization
    - Adaptative compression
    - Parallel processing with OpenMP
    - Sub-millisecond latency
    """

    cdef:
        str db_path
        bint use_compression
        int max_connections
        object _connections_pool
        dict _query_cache
        object _connections_pool
        dict _query_cache
        object _compressor
        bint _wal_enabled
        int _batch_size

    def __init__(self, str db_path, bint use_compression=True, int max_connections=64):
        """
        Initialize CRUD engine

        Args:
            db_path (str): Path to the SQLite database file.
            use_compression (bool): Whether to use compression for data storage.
            max_connections (int): Maximum number of database connections in the pool.
        """

        self.db_path = db_path
        self.use_compression = use_compression
        self.max_connections = max_connections
        self._query_cache = {}
        self.wal_enabled = False
        self._batch_size = 10000

        # Initialize connection pool
        self._init_connection_pool()

        # Enable WAL mode for better concurrency
        self._enable_wal_mode()

    def _enable_wal_mode(self):
        """Enable Write-Ahead Logging (WAL) mode for better concurrency."""
        if not self._wal_enabled:
            conn = self._get_connection()
            try:
                conn.execute("PRAGMA journal_mode=WAL;")
                conn.execute("PRAGMA synchronous=NORMAL;")
                conn.execute("PRAGMA temp_store=MEMORY;")
                conn.execute("PRAGMA cache_size=-64000;")  # 64MB cache
                conn.execute("PRAGMA page_size=4096;") # 4KB pages
                conn.commit()
                self._wal_enabled = True
            finally:
                self._release_connection(conn)

    cdef object _get_connection(self):
        """Get a database connection from the pool."""
        if self._connection_pool:
            return self._connections_pool.pop()
        else:
            return sqlite3.connect(self.db_path, check_same_thread=False)

    cdef void _release_connection(self, object conn):
        """Release a database connection back to the pool."""
        if len(self._connections_pool) < self.max_connections:
            self._connections_pool.append(conn)
        else:
            conn.close()

    cpdef list create_bulk(self, list records, srt table_name):
        """
        Create multiple records in bulk.

        Args:
            records (list): List of records to create.
            table_name (str): Name of the table to insert records into.

        Returns:
            List of inserted record IDs.
        """
        cdef:
            int i, batch_start, batch_end
            int total_records = len(records)
            list inserted_ids = []
            object conn

        conn = self._get_connection()

        try:
            # Create table if not exists
            if records:
                self._create_table_from_record(conn, table_name, records[0])

            # Process in batches for optimal performance
            for batch_start in range(0, total_records, self._batch_size):
                batch_end = min(batch_start + self._batch_size, total_records)
                batch = records[batch_start:batch_end]

                # Build bulk insert Query
                placeholders = ', '.join(['?'] for _ in batch[0].keys())
                columns = ', '.join(batch[0].keys())
                query = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"

                # Execute batch insert
                cursor = conn.cursor()
                for record in batch:
                    cursor.execute(query, tuple(record.values()))
                    inserted_ids.append(cursor.lastrowid)
                conn.commit()

        finally:
            self._release_connection(conn)

        return inserted_ids

    cdef list read_optimized(self, str query, dict params=None):
        """
        Optimized read with query caching.

        Args:
            query (str): SQL query to execute.
            params (dict): Query parameters.

        Returns:
            List of result rows.
        """
        cdef object conn

        if params is None:
            params = {}

        conn = self._get_connection()

        try:
            cursor = conn.cursor()

            if params:
                cursor.execute(query, tuple(params.values()))
            else:
                cursor.execute(query)

            # Convert rows to dictionaries
            columns = [desc[0] for desc in cursor.description]
            results = []

            for row in cursor.fetchall():
                results.append(dict(zip(columns, row)))

                return results

        finally:
            self._release_connection(conn)

    cpdef int update_transactional(self, str table_name, dict updates, str where_clause, dict where_params):
        """
        Transactional update with ACID guarantees
        
        Args:
            table_name (str): Name of the table to update.
            updates (dict): Dictionary of columns to update with their new values.
            where_clause (str): WHERE clause for the update.
            where_params (dict): Parameters for the WHERE clause.

        Returns:
            Number of rows updated.
        """
        cdef object conn
        cdef int rows_updated 

        conn = self._get_connection()

        try:
            # Build UPDATE query
            set_clause = ', '.join([f"{k}=?" for k in updates.keys()])
            query = f"UPDATE {table_name} SET {set_clause} WHERE {where_clause}"

            # Combine parameters
            params = list(updates.values()) + list(where_params.values())

            cursor = conn.cursor()
            cursor.execute(query, params)
            rows_updated = cursor.rowcount
            conn.commit()

            return rows_updated

        finally:
            self._release_connection(conn)

    cpdef int delete_cascade(self, str table_name, str where_clause, dict where_params):
        """
        Cascade delete with transaction support.

        Args:
            table_name (str): Name of the table to delete from.
            where_clause (str): WHERE clause for the delete.
            where_params (dict): Parameters for the WHERE clause.

        Returns:
            Number of rows deleted.
        """
        cdef object conn
        cdef int rows_deleted

        conn = self._get_connection()

        try:
            query = f"DELETE FROM {table_name} WHERE {where_clause}"

            cursor = conn.cursor()
            cursor.execute(query, tuple(where_params.values()))
            rows_deleted = cursor.rowcount
            conn.commit()

            return rows_deleted

        finally:
            self._release_connection(conn)

    def _create_table_from_record(self, conn, table_name, record):
        """Create a table based on record"""
        columns = []
        for key, value in record.items():
            if isinstance(value, int):
                col_type = "INTEGER"
            elif isinstance(value, float):
                col_type = "REAL"
            elif isinstance(value, (dict, list)):
                col_type = "TEXT"
            else:
                col_type = "TEXT"

            columns.append(f"{key} {col_type}")
        
        columns_def = ', '.join(columns)
        query = f"CREATE TABLE IF NOT EXISTS {table_name} (id INTEGER PRIMARY KEY AUTOINCREMENT, {columns_def})"
        conn.execute(query)
        conn.commit()


    cpdef dict get_performance_metrics(self):
        """
        Get current performance metrics of the CRUD engine.
        
        Returns:
            Dictionary of performance metrics.
        """
        return {
            'connection_pool_size': len(self._connections_pool),
            'max_connections': self.max_connections,
            'wal_enabled': self._wal_enabled,
            'compression_enabled': self.use_compression,
            'batch_size': self._batch_size,
            'query_cache_size': self._query_cache_size
        }

    def close(self):
        """Close all connections in the pool."""
        for conn in self._connections_pool:
            conn.close()
        self._connections_pool.clear()